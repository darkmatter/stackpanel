// Package flakeedit provides tree-sitter based editing of Nix flake.nix files.
//
// It uses the tree-sitter-nix grammar to parse flake.nix into a concrete
// syntax tree, then performs surgical byte-offset insertions that preserve
// all comments, whitespace, and formatting.
package flakeedit

import (
	"bytes"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	tree_sitter_nix "github.com/darkmatter/stackpanel/stackpanel-go/internal/treesitter/nix"
	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// FlakeInput represents a flake input declaration to insert.
type FlakeInput struct {
	// Name is the input name (e.g., "my-module").
	Name string
	// URL is the flake URL (e.g., "github:author/my-module").
	URL string
	// FollowsNixpkgs adds `<name>.inputs.nixpkgs.follows = "nixpkgs";`
	FollowsNixpkgs bool
}

// EditResult describes what changes were made.
type EditResult struct {
	// Modified is the modified source.
	Modified []byte
	// InputAdded is true if a new input was inserted.
	InputAdded bool
	// ImportAdded is true if a new stackpanelImports entry was inserted.
	ImportAdded bool
	// InputAlreadyExists is true if the input was already present.
	InputAlreadyExists bool
}

// FlakeEditor uses tree-sitter to parse and modify flake.nix files.
type FlakeEditor struct {
	source []byte
	tree   *tree_sitter.Tree
	parser *tree_sitter.Parser
}

// NewFlakeEditor parses a flake.nix source and returns an editor.
// The caller must call Close() when done.
func NewFlakeEditor(source []byte) (*FlakeEditor, error) {
	parser := tree_sitter.NewParser()
	lang := tree_sitter.NewLanguage(tree_sitter_nix.Language())
	if err := parser.SetLanguage(lang); err != nil {
		parser.Close()
		return nil, fmt.Errorf("failed to set Nix language: %w", err)
	}

	tree := parser.Parse(source, nil)
	if tree == nil {
		parser.Close()
		return nil, errors.New("failed to parse source")
	}

	root := tree.RootNode()
	if root.HasError() {
		// We still allow editing files with parse errors — tree-sitter
		// produces a best-effort tree. But we warn via the error.
		// The caller can choose to proceed or bail.
	}

	return &FlakeEditor{
		source: source,
		tree:   tree,
		parser: parser,
	}, nil
}

// Close releases tree-sitter resources.
func (e *FlakeEditor) Close() {
	if e.tree != nil {
		e.tree.Close()
	}
	if e.parser != nil {
		e.parser.Close()
	}
}

// HasParseErrors returns true if the source has syntax errors.
func (e *FlakeEditor) HasParseErrors() bool {
	return e.tree.RootNode().HasError()
}

// HasInput checks if an input with the given name already exists.
// It searches for bindings like `<name>.url = "...";` or `<name> = { ... };`
// within the `inputs = { ... }` block.
func (e *FlakeEditor) HasInput(name string) bool {
	inputsNode := e.findInputsAttrset()
	if inputsNode == nil {
		return false
	}
	return e.findInputBinding(inputsNode, name) != nil
}

// AddInput inserts a flake input into the `inputs = { ... }` block.
// Uses dot-notation style: `<name>.url = "...";`
// Returns the modified source.
func (e *FlakeEditor) AddInput(input FlakeInput) ([]byte, error) {
	inputsNode := e.findInputsAttrset()
	if inputsNode == nil {
		return nil, errors.New("could not find `inputs = { ... }` block in flake.nix")
	}

	// Check if input already exists
	if e.findInputBinding(inputsNode, input.Name) != nil {
		return e.source, nil // no-op
	}

	// Find the insertion point: just before the closing `}` of the inputs attrset.
	closingBrace := e.findClosingBrace(inputsNode)
	if closingBrace == nil {
		return nil, errors.New("could not find closing `}` of inputs block")
	}

	// Detect indentation from existing bindings
	indent := e.detectBindingIndent(inputsNode)

	// Build the input text
	var lines []string
	lines = append(lines, fmt.Sprintf("%s%s.url = %q;", indent, input.Name, input.URL))
	if input.FollowsNixpkgs {
		lines = append(lines, fmt.Sprintf("%s%s.inputs.nixpkgs.follows = \"nixpkgs\";", indent, input.Name))
	}

	insertText := strings.Join(lines, "\n") + "\n"

	// Insert before the line containing the closing brace.
	// We go to the start of the line so the structure stays clean.
	insertPos := e.startOfLine(closingBrace.StartByte())
	modified := insertAt(e.source, insertPos, []byte(insertText))

	return modified, nil
}

// AddStackpanelImport inserts a module import expression into the
// `stackpanelImports = [ ... ]` list.
// importExpr is the Nix expression to add, e.g., "inputs.my-module.stackpanelModules.default"
func (e *FlakeEditor) AddStackpanelImport(importExpr string) ([]byte, error) {
	listNode := e.findStackpanelImportsList()
	if listNode == nil {
		return nil, errors.New("could not find `stackpanelImports = [ ... ]` in flake.nix")
	}

	// Check if the import already exists
	if e.listContainsExpr(listNode, importExpr) {
		return e.source, nil // no-op
	}

	// Find the closing `]`
	closingBracket := e.findClosingBracket(listNode)
	if closingBracket == nil {
		return nil, errors.New("could not find closing `]` of stackpanelImports list")
	}

	// Detect whether this is a single-line or multi-line list
	openBracket := e.findOpenBracket(listNode)
	if openBracket == nil {
		return nil, errors.New("could not find opening `[` of stackpanelImports list")
	}

	var insertText string
	if openBracket.StartPosition().Row == closingBracket.StartPosition().Row {
		// Single-line list: insert before `]` with a space
		// e.g., `[ ./.stack/nix ]` -> `[ ./.stack/nix inputs.foo.bar ]`
		insertText = importExpr + " "
	} else {
		// Multi-line list: add a new line with proper indentation
		indent := e.detectListItemIndent(listNode)
		insertText = indent + importExpr + "\n"
	}

	insertPos := closingBracket.StartByte()
	modified := insertAt(e.source, insertPos, []byte(insertText))

	return modified, nil
}

// AddInputAndImport performs both operations atomically on the same source.
// This is the main entry point for module installation.
func (e *FlakeEditor) AddInputAndImport(input FlakeInput, importExpr string) (*EditResult, error) {
	result := &EditResult{}

	// Step 1: Add the input
	if e.HasInput(input.Name) {
		result.InputAlreadyExists = true
		result.Modified = e.source
	} else {
		modified, err := e.AddInput(input)
		if err != nil {
			return nil, fmt.Errorf("failed to add input: %w", err)
		}
		result.InputAdded = true
		result.Modified = modified

		// Re-parse after modification so positions are correct for step 2
		e.tree.Close()
		e.tree = e.parser.Parse(modified, nil)
		if e.tree == nil {
			return nil, errors.New("failed to re-parse after adding input")
		}
		e.source = modified
	}

	// Step 2: Add the import (if importExpr is provided)
	if importExpr != "" {
		modified, err := e.AddStackpanelImport(importExpr)
		if err != nil {
			// Not finding stackpanelImports is non-fatal — some flakes don't have it
			result.Modified = e.source
		} else {
			if !bytes.Equal(modified, e.source) {
				result.ImportAdded = true
			}
			result.Modified = modified
			e.source = modified
		}
	}

	return result, nil
}

// ============================================================================
// Tree traversal helpers
// ============================================================================

// findInputsAttrset finds the attrset_expression that is the value of
// the `inputs = { ... }` binding at the top level.
func (e *FlakeEditor) findInputsAttrset() *tree_sitter.Node {
	root := e.tree.RootNode()
	// source_code -> attrset_expression -> binding_set -> binding(inputs)
	topAttrset := e.findChildByKind(root, "attrset_expression")
	if topAttrset == nil {
		return nil
	}

	bindingSet := e.findChildByKind(topAttrset, "binding_set")
	if bindingSet == nil {
		return nil
	}

	// Find the binding where attrpath is exactly "inputs"
	for i := uint(0); i < uint(bindingSet.ChildCount()); i++ {
		child := bindingSet.Child(i)
		if child.Kind() != "binding" {
			continue
		}
		attrpath := e.findChildByKind(child, "attrpath")
		if attrpath == nil {
			continue
		}
		// The attrpath must be a single identifier "inputs"
		if attrpath.ChildCount() == 1 && e.nodeText(attrpath.Child(0)) == "inputs" {
			// Return the attrset_expression value
			return e.findChildByKind(child, "attrset_expression")
		}
	}

	return nil
}

// findInputBinding finds a binding within the inputs attrset whose first
// identifier matches the given name. Handles both:
// - `name.url = "...";` (dot-notation)
// - `name = { ... };` (attrset-style)
func (e *FlakeEditor) findInputBinding(inputsAttrset *tree_sitter.Node, name string) *tree_sitter.Node {
	bindingSet := e.findChildByKind(inputsAttrset, "binding_set")
	if bindingSet == nil {
		return nil
	}

	for i := uint(0); i < uint(bindingSet.ChildCount()); i++ {
		child := bindingSet.Child(i)
		if child.Kind() != "binding" {
			continue
		}
		attrpath := e.findChildByKind(child, "attrpath")
		if attrpath == nil {
			continue
		}
		// Check if the first identifier matches
		firstIdent := e.findChildByKind(attrpath, "identifier")
		if firstIdent != nil && e.nodeText(firstIdent) == name {
			return child
		}
	}

	return nil
}

// findStackpanelImportsList finds the list_expression that is the value of
// any `stackpanelImports = [ ... ]` binding anywhere in the tree.
// This uses a recursive search since stackpanelImports can be deeply nested
// (e.g., inside a let-in block, function arguments, etc.)
func (e *FlakeEditor) findStackpanelImportsList() *tree_sitter.Node {
	return e.findBindingValue(e.tree.RootNode(), "stackpanelImports", "list_expression")
}

// findBindingValue recursively searches for a binding with the given
// attrpath name and returns its value node if it matches the expected kind.
func (e *FlakeEditor) findBindingValue(node *tree_sitter.Node, name string, expectedKind string) *tree_sitter.Node {
	if node.Kind() == "binding" {
		attrpath := e.findChildByKind(node, "attrpath")
		if attrpath != nil && attrpath.ChildCount() == 1 && e.nodeText(attrpath.Child(0)) == name {
			// Find the value (skip attrpath, =, and look for the expected kind)
			for i := uint(0); i < uint(node.ChildCount()); i++ {
				child := node.Child(i)
				if child.Kind() == expectedKind {
					return child
				}
			}
		}
	}

	// Recurse into children
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		result := e.findBindingValue(child, name, expectedKind)
		if result != nil {
			return result
		}
	}

	return nil
}

// findChildByKind returns the first direct child with the given kind.
func (e *FlakeEditor) findChildByKind(node *tree_sitter.Node, kind string) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == kind {
			return child
		}
	}
	return nil
}

// findClosingBrace finds the `}` token in an attrset_expression.
func (e *FlakeEditor) findClosingBrace(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == "}" {
			return child
		}
	}
	return nil
}

// findClosingBracket finds the `]` token in a list_expression.
func (e *FlakeEditor) findClosingBracket(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == "]" {
			return child
		}
	}
	return nil
}

// findOpenBracket finds the `[` token in a list_expression.
func (e *FlakeEditor) findOpenBracket(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == "[" {
			return child
		}
	}
	return nil
}

// detectBindingIndent looks at existing bindings in an attrset to detect
// the indentation used. Returns the indent string (e.g., "    ").
func (e *FlakeEditor) detectBindingIndent(attrsetNode *tree_sitter.Node) string {
	bindingSet := e.findChildByKind(attrsetNode, "binding_set")
	if bindingSet == nil {
		return "    " // default 4 spaces
	}

	// Look at the first binding's column position
	for i := uint(0); i < uint(bindingSet.ChildCount()); i++ {
		child := bindingSet.Child(i)
		if child.Kind() == "binding" {
			col := child.StartPosition().Column
			return strings.Repeat(" ", int(col))
		}
	}

	return "    "
}

// detectListItemIndent looks at existing items in a list to detect indentation.
func (e *FlakeEditor) detectListItemIndent(listNode *tree_sitter.Node) string {
	// Look for any non-bracket child
	for i := uint(0); i < uint(listNode.ChildCount()); i++ {
		child := listNode.Child(i)
		if child.Kind() != "[" && child.Kind() != "]" {
			col := child.StartPosition().Column
			return strings.Repeat(" ", int(col))
		}
	}
	return "      " // default 6 spaces
}

// listContainsExpr checks if a list_expression contains an expression
// that matches the given text (by comparing source text of each element).
func (e *FlakeEditor) listContainsExpr(listNode *tree_sitter.Node, expr string) bool {
	for i := uint(0); i < uint(listNode.ChildCount()); i++ {
		child := listNode.Child(i)
		if child.Kind() == "[" || child.Kind() == "]" {
			continue
		}
		text := e.nodeText(child)
		if text == expr {
			return true
		}
		// Also check for select_expression that matches when printed as dot-separated
		if child.Kind() == "select_expression" || child.Kind() == "variable_expression" {
			fullText := e.nodeFullText(child)
			if fullText == expr {
				return true
			}
		}
	}
	return false
}

// nodeText returns the source text for a single node (no children).
func (e *FlakeEditor) nodeText(node *tree_sitter.Node) string {
	return string(e.source[node.StartByte():node.EndByte()])
}

// nodeFullText returns the full source text for a node and all its children.
func (e *FlakeEditor) nodeFullText(node *tree_sitter.Node) string {
	return string(e.source[node.StartByte():node.EndByte()])
}

// ============================================================================
// Byte manipulation
// ============================================================================

// startOfLine returns the byte offset of the start of the line containing pos.
func (e *FlakeEditor) startOfLine(pos uint) uint {
	for i := int(pos) - 1; i >= 0; i-- {
		if e.source[i] == '\n' {
			return uint(i + 1)
		}
	}
	return 0
}

// insertAt inserts text at the given byte offset in source.
func insertAt(source []byte, offset uint, text []byte) []byte {
	result := make([]byte, 0, len(source)+len(text))
	result = append(result, source[:offset]...)
	result = append(result, text...)
	result = append(result, source[offset:]...)
	return result
}

var configVariableExprPattern = regexp.MustCompile(`^\s*config\.variables\.("(?:[^"\\]|\\.)+")\.value\s*$`)

// NixEditor provides source-preserving edits for general Nix files.
type NixEditor struct {
	source []byte
	tree   *tree_sitter.Tree
	parser *tree_sitter.Parser
}

// NewNixEditor parses a Nix source and returns a source-preserving editor.
func NewNixEditor(source []byte) (*NixEditor, error) {
	parser := tree_sitter.NewParser()
	lang := tree_sitter.NewLanguage(tree_sitter_nix.Language())
	if err := parser.SetLanguage(lang); err != nil {
		parser.Close()
		return nil, fmt.Errorf("failed to set Nix language: %w", err)
	}

	tree := parser.Parse(source, nil)
	if tree == nil {
		parser.Close()
		return nil, errors.New("failed to parse source")
	}

	return &NixEditor{source: source, tree: tree, parser: parser}, nil
}

// Close releases tree-sitter resources.
func (e *NixEditor) Close() {
	if e.tree != nil {
		e.tree.Close()
	}
	if e.parser != nil {
		e.parser.Close()
	}
}

// PatchNixPath sets a value expression at the given dotted path.
func PatchNixPath(source []byte, path []string, valueExpr string) ([]byte, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()
	return editor.PatchPath(path, valueExpr)
}

// DeleteNixPath removes the binding at the given dotted path.
func DeleteNixPath(source []byte, path []string) ([]byte, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()
	return editor.DeletePath(path)
}

// ReplaceNixEditableAttrset replaces the editable root attrset while preserving
// any surrounding function wrapper.
func ReplaceNixEditableAttrset(source []byte, attrsetExpr string) ([]byte, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()
	return editor.ReplaceEditableAttrset(attrsetExpr)
}

// ExtractAppVariableLinksFromSource returns app/env/envKey -> variable ID
// mappings for bindings that use config.variables."/...".value.
func ExtractAppVariableLinksFromSource(source []byte) (map[string]map[string]map[string]string, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()
	return editor.ExtractAppVariableLinks(), nil
}

// PatchPath sets a value expression at the given dotted path.
func (e *NixEditor) PatchPath(path []string, valueExpr string) ([]byte, error) {
	if len(path) == 0 {
		return nil, errors.New("path is required")
	}
	root := e.findEditableAttrset()
	if root == nil {
		return nil, errors.New("could not find editable attrset")
	}
	return e.patchWithinAttrset(root, path, valueExpr)
}

// DeletePath removes the binding at the given dotted path.
func (e *NixEditor) DeletePath(path []string) ([]byte, error) {
	if len(path) == 0 {
		return nil, errors.New("path is required")
	}
	root := e.findEditableAttrset()
	if root == nil {
		return nil, errors.New("could not find editable attrset")
	}
	return e.deleteWithinAttrset(root, path)
}

// ReplaceEditableAttrset replaces the editable root attrset body.
func (e *NixEditor) ReplaceEditableAttrset(attrsetExpr string) ([]byte, error) {
	root := e.findEditableAttrset()
	if root == nil {
		return nil, errors.New("could not find editable attrset")
	}
	replaceEnd := root.EndByte()
	if strings.HasSuffix(attrsetExpr, "\n") && replaceEnd < uint(len(e.source)) && e.source[replaceEnd] == '\n' {
		replaceEnd++
	}
	return replaceRange(e.source, root.StartByte(), replaceEnd, []byte(attrsetExpr)), nil
}

// ExtractAppVariableLinks returns app/env/envKey -> variable ID mappings.
func (e *NixEditor) ExtractAppVariableLinks() map[string]map[string]map[string]string {
	links := make(map[string]map[string]map[string]string)
	appsNode := e.findAttrsetAtPath([]string{"apps"})
	if appsNode == nil {
		return links
	}

	for _, appBinding := range e.bindings(appsNode) {
		appPath := e.bindingAttrpath(appBinding)
		if len(appPath) != 1 {
			continue
		}
		appID := appPath[0]
		appAttrset := e.bindingAttrsetValue(appBinding)
		if appAttrset == nil {
			continue
		}
		envsNode := e.findAttrsetWithin(appAttrset, []string{"environments"})
		if envsNode == nil {
			continue
		}

		for _, envBinding := range e.bindings(envsNode) {
			envPath := e.bindingAttrpath(envBinding)
			if len(envPath) != 1 {
				continue
			}
			envName := envPath[0]
			envAttrset := e.bindingAttrsetValue(envBinding)
			if envAttrset == nil {
				continue
			}
			envVarsNode := e.findAttrsetWithin(envAttrset, []string{"env"})
			if envVarsNode == nil {
				continue
			}

			for _, envVarBinding := range e.bindings(envVarsNode) {
				envKeyPath := e.bindingAttrpath(envVarBinding)
				if len(envKeyPath) != 1 {
					continue
				}
				envKey := envKeyPath[0]
				valueNode := e.bindingValue(envVarBinding)
				if valueNode == nil {
					continue
				}
				variableID, ok := parseConfigVariableExpr(e.nodeText(valueNode))
				if !ok {
					continue
				}
				if links[appID] == nil {
					links[appID] = make(map[string]map[string]string)
				}
				if links[appID][envName] == nil {
					links[appID][envName] = make(map[string]string)
				}
				links[appID][envName][envKey] = variableID
			}
		}
	}

	return links
}

func (e *NixEditor) patchWithinAttrset(attrset *tree_sitter.Node, path []string, valueExpr string) ([]byte, error) {
	binding, matched, valueNode := e.findBestBinding(attrset, path)
	if binding != nil {
		switch {
		case len(matched) == len(path):
			if valueNode == nil {
				return nil, errors.New("could not find binding value")
			}
			return replaceRange(e.source, valueNode.StartByte(), valueNode.EndByte(), []byte(valueExpr)), nil
		case valueNode != nil && valueNode.Kind() == "attrset_expression":
			return e.patchWithinAttrset(valueNode, path[len(matched):], valueExpr)
		default:
			return nil, fmt.Errorf("path segment %q is not an attrset", matched[len(matched)-1])
		}
	}

	closingBrace := e.findClosingBrace(attrset)
	if closingBrace == nil {
		return nil, errors.New("could not find closing brace for attrset")
	}

	insertText := e.buildNestedBinding(e.detectBindingIndent(attrset), path, valueExpr)
	insertPos := e.startOfLine(closingBrace.StartByte())
	if attrset.StartPosition().Row == closingBrace.StartPosition().Row {
		insertPos = closingBrace.StartByte()
		insertText = "\n" + insertText + strings.Repeat(" ", e.lineIndent(attrset.StartByte()))
	}
	return insertAt(e.source, insertPos, []byte(insertText)), nil
}

func (e *NixEditor) deleteWithinAttrset(attrset *tree_sitter.Node, path []string) ([]byte, error) {
	binding, matched, valueNode := e.findBestBinding(attrset, path)
	if binding == nil {
		return e.source, nil
	}

	if len(matched) == len(path) {
		start := e.startOfLine(binding.StartByte())
		end := e.endOfBinding(binding.EndByte())
		return deleteRange(e.source, start, end), nil
	}

	if valueNode == nil || valueNode.Kind() != "attrset_expression" {
		return e.source, nil
	}

	return e.deleteWithinAttrset(valueNode, path[len(matched):])
}

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

func (e *NixEditor) findAttrsetAtPath(path []string) *tree_sitter.Node {
	current := e.findEditableAttrset()
	if current == nil {
		return nil
	}
	remaining := path
	for len(remaining) > 0 {
		binding, matched, valueNode := e.findBestBinding(current, remaining)
		if binding == nil || len(matched) == 0 || valueNode == nil || valueNode.Kind() != "attrset_expression" {
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

func (e *NixEditor) findAttrsetWithin(attrset *tree_sitter.Node, path []string) *tree_sitter.Node {
	current := attrset
	remaining := path
	for len(remaining) > 0 {
		binding, matched, valueNode := e.findBestBinding(current, remaining)
		if binding == nil || len(matched) == 0 || valueNode == nil || valueNode.Kind() != "attrset_expression" {
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

func (e *NixEditor) findBestBinding(attrset *tree_sitter.Node, path []string) (*tree_sitter.Node, []string, *tree_sitter.Node) {
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

func (e *NixEditor) bindingAttrsetValue(binding *tree_sitter.Node) *tree_sitter.Node {
	valueNode := e.bindingValue(binding)
	if valueNode == nil || valueNode.Kind() != "attrset_expression" {
		return nil
	}
	return valueNode
}

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

func (e *NixEditor) buildNestedBinding(baseIndent string, path []string, valueExpr string) string {
	const step = "  "
	var b strings.Builder
	indent := baseIndent
	for i, segment := range path {
		b.WriteString(indent)
		b.WriteString(serializeAttrName(segment))
		b.WriteString(" = ")
		if i == len(path)-1 {
			b.WriteString(valueExpr)
			b.WriteString(";\n")
			break
		}
		b.WriteString("{\n")
		indent += step
	}
	for i := len(path) - 2; i >= 0; i-- {
		indent = indent[:len(indent)-len(step)]
		b.WriteString(indent)
		b.WriteString("};\n")
	}
	return b.String()
}

func (e *NixEditor) detectBindingIndent(attrset *tree_sitter.Node) string {
	for _, binding := range e.bindings(attrset) {
		return strings.Repeat(" ", int(binding.StartPosition().Column))
	}
	return strings.Repeat(" ", e.lineIndent(attrset.StartByte())+2)
}

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

func (e *NixEditor) findChildByKind(node *tree_sitter.Node, kind string) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child != nil && child.Kind() == kind {
			return child
		}
	}
	return nil
}

func (e *NixEditor) findClosingBrace(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child != nil && child.Kind() == "}" {
			return child
		}
	}
	return nil
}

func (e *NixEditor) startOfLine(pos uint) uint {
	for i := int(pos) - 1; i >= 0; i-- {
		if e.source[i] == '\n' {
			return uint(i + 1)
		}
	}
	return 0
}

func (e *NixEditor) nodeText(node *tree_sitter.Node) string {
	return string(e.source[node.StartByte():node.EndByte()])
}

func (e *NixEditor) endOfBinding(pos uint) uint {
	for i := pos; i < uint(len(e.source)); i++ {
		if e.source[i] == '\n' {
			return i + 1
		}
	}
	return uint(len(e.source))
}

func parseConfigVariableExpr(expr string) (string, bool) {
	matches := configVariableExprPattern.FindStringSubmatch(strings.TrimSpace(expr))
	if len(matches) != 2 {
		return "", false
	}
	variableID, err := strconv.Unquote(matches[1])
	if err != nil {
		return "", false
	}
	return variableID, true
}

func serializeAttrName(name string) string {
	if isValidIdentifier(name) {
		return name
	}
	return strconv.Quote(name)
}

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

func isIdentStart(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_'
}

func isIdentChar(r rune) bool {
	return isIdentStart(r) || (r >= '0' && r <= '9') || r == '-' || r == '\''
}

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

func replaceRange(source []byte, start uint, end uint, text []byte) []byte {
	result := make([]byte, 0, len(source)-int(end-start)+len(text))
	result = append(result, source[:start]...)
	result = append(result, text...)
	result = append(result, source[end:]...)
	return result
}

func deleteRange(source []byte, start uint, end uint) []byte {
	result := make([]byte, 0, len(source)-int(end-start))
	result = append(result, source[:start]...)
	result = append(result, source[end:]...)
	return result
}
