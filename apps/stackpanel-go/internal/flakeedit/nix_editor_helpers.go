package flakeedit

import (
	"sort"
	"strconv"
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// findEditableAttrset locates the last top-level attrset in the parse tree.
// "Top-level" means not nested inside another attrset. We pick the *last* one
// because Nix config files like { config, ... }: { ... } have the function
// formals as the first attrset-like construct and the body as the last.
func (e *NixEditor) findEditableAttrset() *tree_sitter.Node {
	var candidates []*tree_sitter.Node

	var walk func(node *tree_sitter.Node, hasAttrsetAncestor bool)
	walk = func(node *tree_sitter.Node, hasAttrsetAncestor bool) {
		if node == nil {
			return
		}

		isAttrset := node.Kind() == "attrset_expression"
		if isAttrset && !hasAttrsetAncestor {
			candidates = append(candidates, node)
		}

		for i := uint(0); i < uint(node.ChildCount()); i++ {
			walk(node.Child(i), hasAttrsetAncestor || isAttrset)
		}
	}

	walk(e.tree.RootNode(), false)

	if len(candidates) == 0 {
		return nil
	}

	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].StartByte() < candidates[j].StartByte()
	})

	return candidates[len(candidates)-1]
}

// findAttrsetAtPath resolves an attrset path under the editable root.
func (e *NixEditor) findAttrsetAtPath(path []string) *tree_sitter.Node {
	current := e.findEditableAttrset()
	if current == nil {
		return nil
	}

	remaining := path
	for len(remaining) > 0 {
		binding, matched, valueNode := e.findBestBinding(current, remaining)
		if binding == nil || len(matched) == 0 || valueNode == nil ||
			valueNode.Kind() != "attrset_expression" {
			return nil
		}

		if len(matched) == len(remaining) {
			return valueNode
		}

		current = valueNode
		remaining = remaining[len(matched):]
	}

	return current
}

// findAttrsetWithin descends to a nested attrset inside another attrset.
func (e *NixEditor) findAttrsetWithin(
	attrset *tree_sitter.Node,
	path []string,
) *tree_sitter.Node {
	current := attrset
	remaining := path
	for len(remaining) > 0 {
		binding, matched, valueNode := e.findBestBinding(current, remaining)
		if binding == nil || len(matched) == 0 || valueNode == nil ||
			valueNode.Kind() != "attrset_expression" {
			return nil
		}

		if len(matched) == len(remaining) {
			return valueNode
		}

		current = valueNode
		remaining = remaining[len(matched):]
	}

	return current
}

// findBestBinding finds the binding whose attrpath is the longest prefix of path.
// Nix allows both `a.b.c = 1;` and `a = { b.c = 1; };` - this handles both
// by matching the longest key and letting callers recurse into nested attrsets.
func (e *NixEditor) findBestBinding(
	attrset *tree_sitter.Node,
	path []string,
) (*tree_sitter.Node, []string, *tree_sitter.Node) {
	var bestBinding *tree_sitter.Node
	var bestPath []string
	var bestValue *tree_sitter.Node

	for _, binding := range e.bindings(attrset) {
		attrpath := e.bindingAttrpath(binding)
		if len(attrpath) == 0 || len(attrpath) > len(path) {
			continue
		}

		if !pathsEqual(attrpath, path[:len(attrpath)]) {
			continue
		}

		if len(attrpath) > len(bestPath) {
			bestBinding = binding
			bestPath = attrpath
			bestValue = e.bindingValue(binding)
		}
	}

	return bestBinding, bestPath, bestValue
}

// hasSiblingPrefixCollision reports whether any existing binding in attrset
// already uses the first segment of path as the head of its attrpath (e.g. a
// sibling `ide.zed.enable = true;` when we are about to insert under `ide`).
//
// When this is true, inserting a fresh nested `ide = { ... };` block would add a
// second top-level `ide` attribute, which Nix rejects ("attribute 'ide' already
// defined") and which clobbers the existing value. Callers must instead insert
// the new binding in dotted notation so it merges with the sibling.
//
// Note: a sibling that binds the segment directly as an attrset (attrpath ==
// [segment]) is handled earlier by findBestBinding, which recurses into that
// attrset rather than reaching the insert path. Any collision detected here is
// therefore necessarily a longer dotted path that diverges further down, and
// dotted insertion always merges cleanly with such a sibling.
func (e *NixEditor) hasSiblingPrefixCollision(
	attrset *tree_sitter.Node,
	path []string,
) bool {
	if len(path) == 0 {
		return false
	}

	for _, binding := range e.bindings(attrset) {
		attrpath := e.bindingAttrpath(binding)
		if len(attrpath) > 0 && attrpath[0] == path[0] {
			return true
		}
	}

	return false
}

// bindings extracts all first-level bindings from an attrset.
func (e *NixEditor) bindings(attrset *tree_sitter.Node) []*tree_sitter.Node {
	bindingSet := e.findChildByKind(attrset, "binding_set")
	if bindingSet == nil {
		return nil
	}

	var bindings []*tree_sitter.Node
	for i := uint(0); i < uint(bindingSet.ChildCount()); i++ {
		child := bindingSet.Child(i)
		if child != nil && child.Kind() == "binding" {
			bindings = append(bindings, child)
		}
	}

	return bindings
}

// bindingValue returns the non-key child node of a binding.
func (e *NixEditor) bindingValue(binding *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(binding.ChildCount()); i++ {
		child := binding.Child(i)
		if child == nil || child.Kind() == "attrpath" || !child.IsNamed() {
			continue
		}
		return child
	}

	return nil
}

// bindingAttrsetValue returns the value node only when it is an attrset.
func (e *NixEditor) bindingAttrsetValue(binding *tree_sitter.Node) *tree_sitter.Node {
	valueNode := e.bindingValue(binding)
	if valueNode == nil || valueNode.Kind() != "attrset_expression" {
		return nil
	}
	return valueNode
}

// bindingAttrpath returns a binding's key as path segments. Handles both bare
// identifiers (foo) and quoted strings ("foo-bar"), unquoting as needed.
func (e *NixEditor) bindingAttrpath(binding *tree_sitter.Node) []string {
	attrpath := e.findChildByKind(binding, "attrpath")
	if attrpath == nil {
		return nil
	}

	var segments []string
	for i := uint(0); i < uint(attrpath.ChildCount()); i++ {
		child := attrpath.Child(i)
		if child == nil || !child.IsNamed() {
			continue
		}

		text := strings.TrimSpace(e.nodeText(child))
		if text == "" {
			continue
		}

		if unquoted, err := strconv.Unquote(text); err == nil {
			text = unquoted
		}

		segments = append(segments, text)
	}

	return segments
}

// buildDottedBinding renders a path as a single dotted Nix binding:
//
//	path=["ide","vscode","enable"] value="true"  ->  "ide.vscode.enable = true;\n"
//
// Dotted form is used when a sibling binding already defines another leaf under
// the same leading segment, because Nix merges sibling dotted paths (e.g.
// `ide.zed.enable = true;` alongside `ide.vscode.enable = true;`) but rejects
// mixing a dotted path with a fresh `ide = { ... };` block for the same key.
func (e *NixEditor) buildDottedBinding(
	baseIndent string,
	path []string,
	valueExpr string,
) string {
	segments := make([]string, len(path))
	for i, segment := range path {
		segments[i] = serializeAttrName(segment)
	}

	return baseIndent + strings.Join(segments, ".") + " = " + valueExpr + ";\n"
}

// detectBindingIndent inspects existing bindings to infer insertion indentation.
func (e *NixEditor) detectBindingIndent(attrset *tree_sitter.Node) string {
	for _, binding := range e.bindings(attrset) {
		return strings.Repeat(" ", int(binding.StartPosition().Column))
	}

	return strings.Repeat(" ", e.lineIndent(attrset.StartByte())+2)
}

// lineIndent returns indentation at the start of the line containing pos.
func (e *NixEditor) lineIndent(pos uint) int {
	lineStart := e.startOfLine(pos)
	indent := 0

	for i := lineStart; i < uint(len(e.source)); i++ {
		switch e.source[i] {
		case ' ':
			indent++
		case '\t':
			indent++
		default:
			return indent
		}
	}

	return indent
}

// startOfLine returns the byte offset for the start of the line containing pos.
func (e *NixEditor) startOfLine(pos uint) uint {
	for i := int(pos) - 1; i >= 0; i-- {
		if e.source[i] == '\n' {
			return uint(i + 1)
		}
	}

	return 0
}

// nodeText extracts source for a single node.
func (e *NixEditor) nodeText(node *tree_sitter.Node) string {
	return string(e.source[node.StartByte():node.EndByte()])
}

// endOfBinding advances to the end of the line after a binding.
func (e *NixEditor) endOfBinding(pos uint) uint {
	for i := pos; i < uint(len(e.source)); i++ {
		if e.source[i] == '\n' {
			return i + 1
		}
	}

	return uint(len(e.source))
}

// findChildByKind returns first direct child node with the given kind.
func (e *NixEditor) findChildByKind(
	node *tree_sitter.Node,
	kind string,
) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child != nil && child.Kind() == kind {
			return child
		}
	}

	return nil
}

// findClosingBrace locates the `}` token node in an attrset.
func (e *NixEditor) findClosingBrace(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child != nil && child.Kind() == "}" {
			return child
		}
	}

	return nil
}

// serializeAttrName returns a valid Nix attrname literal. Names with special
// characters (dashes, dots) are quoted; simple identifiers are left bare.
func serializeAttrName(name string) string {
	if isValidIdentifier(name) {
		return name
	}
	return strconv.Quote(name)
}

// isValidIdentifier checks whether a string fits a simple Nix identifier rule.
func isValidIdentifier(s string) bool {
	if s == "" {
		return false
	}

	for i, r := range s {
		if i == 0 {
			if !isIdentStart(r) {
				return false
			}
			continue
		}

		if !isIdentChar(r) {
			return false
		}
	}

	return true
}

// isIdentStart checks the first rune in an unquoted Nix identifier.
func isIdentStart(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_'
}

// isIdentChar checks subsequent runes in an unquoted Nix identifier.
// Note: Nix allows dashes and single-quotes in identifiers (e.g. "my-pkg" or "sha256'"),
// which is unusual compared to most languages.
func isIdentChar(r rune) bool {
	return isIdentStart(r) || (r >= '0' && r <= '9') || r == '-' || r == '\''
}

// pathsEqual compares two path slices.
func pathsEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}

	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}

	return true
}
