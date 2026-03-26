package flakeedit

import (
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// findInputsAttrset locates the `inputs = { ... }` attrset in the top-level
// flake structure.
func (e *FlakeEditor) findInputsAttrset() *tree_sitter.Node {
	root := e.tree.RootNode()
	topAttrset := e.findChildByKind(root, "attrset_expression")
	if topAttrset == nil {
		return nil
	}

	bindingSet := e.findChildByKind(topAttrset, "binding_set")
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

		if attrpath.ChildCount() == 1 && e.nodeText(attrpath.Child(0)) == "inputs" {
			return e.findChildByKind(child, "attrset_expression")
		}
	}

	return nil
}

// findInputBinding returns the first matching binding for `name` in the inputs
// attrset. It matches on the first identifier segment, so it finds both
// `my-input.url = ...` (dot notation) and `my-input = { url = ...; }` (nested).
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

		firstIdent := e.findChildByKind(attrpath, "identifier")
		if firstIdent != nil && e.nodeText(firstIdent) == name {
			return child
		}
	}

	return nil
}

// findStackpanelImportsList recursively searches for `stackpanelImports = [ ... ]`
// anywhere in the tree. The recursive search is needed because it may be nested
// inside outputs or a let binding depending on the flake structure.
func (e *FlakeEditor) findStackpanelImportsList() *tree_sitter.Node {
	return e.findBindingValue(e.tree.RootNode(), "stackpanelImports", "list_expression")
}

// findBindingValue traverses the tree and returns a binding value node for the
// named attrpath when the node kind matches `expectedKind`.
func (e *FlakeEditor) findBindingValue(node *tree_sitter.Node, name string, expectedKind string) *tree_sitter.Node {
	if node.Kind() == "binding" {
		attrpath := e.findChildByKind(node, "attrpath")
		if attrpath != nil && attrpath.ChildCount() == 1 && e.nodeText(attrpath.Child(0)) == name {
			for i := uint(0); i < uint(node.ChildCount()); i++ {
				child := node.Child(i)
				if child.Kind() == expectedKind {
					return child
				}
			}
		}
	}

	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		result := e.findBindingValue(child, name, expectedKind)
		if result != nil {
			return result
		}
	}

	return nil
}

// findChildByKind returns the first direct child node of the requested grammar kind.
func (e *FlakeEditor) findChildByKind(node *tree_sitter.Node, kind string) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == kind {
			return child
		}
	}

	return nil
}

// findClosingBrace finds the token node for `}` in an attrset expression.
func (e *FlakeEditor) findClosingBrace(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == "}" {
			return child
		}
	}

	return nil
}

// findClosingBracket finds the `]` token node in a list expression.
func (e *FlakeEditor) findClosingBracket(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == "]" {
			return child
		}
	}

	return nil
}

// findOpenBracket finds the `[` token node in a list expression.
func (e *FlakeEditor) findOpenBracket(node *tree_sitter.Node) *tree_sitter.Node {
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		if child.Kind() == "[" {
			return child
		}
	}

	return nil
}

// detectBindingIndent infers indentation from existing input bindings.
func (e *FlakeEditor) detectBindingIndent(attrsetNode *tree_sitter.Node) string {
	bindingSet := e.findChildByKind(attrsetNode, "binding_set")
	if bindingSet == nil {
		return "    "
	}

	for i := uint(0); i < uint(bindingSet.ChildCount()); i++ {
		child := bindingSet.Child(i)
		if child.Kind() == "binding" {
			col := child.StartPosition().Column
			return strings.Repeat(" ", int(col))
		}
	}

	return "    "
}

// detectListItemIndent infers indentation from existing list items.
func (e *FlakeEditor) detectListItemIndent(listNode *tree_sitter.Node) string {
	for i := uint(0); i < uint(listNode.ChildCount()); i++ {
		child := listNode.Child(i)
		if child.Kind() != "[" && child.Kind() != "]" {
			col := child.StartPosition().Column
			return strings.Repeat(" ", int(col))
		}
	}

	return "      "
}

// listContainsExpr checks whether any list element's source text matches expr.
// This is a textual comparison, not semantic - `inputs.foo` and `inputs .foo`
// would not match. In practice, machine-generated expressions are consistent.
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

		if child.Kind() == "select_expression" || child.Kind() == "variable_expression" {
			fullText := e.nodeFullText(child)
			if fullText == expr {
				return true
			}
		}
	}

	return false
}

// nodeText returns raw source bytes covered by the node.
func (e *FlakeEditor) nodeText(node *tree_sitter.Node) string {
	return string(e.source[node.StartByte():node.EndByte()])
}

// nodeFullText returns source bytes for the node span. Functionally identical
// to nodeText since tree-sitter node byte ranges always include children.
func (e *FlakeEditor) nodeFullText(node *tree_sitter.Node) string {
	return string(e.source[node.StartByte():node.EndByte()])
}

// startOfLine returns the offset of the line start for a byte position.
func (e *FlakeEditor) startOfLine(pos uint) uint {
	for i := int(pos) - 1; i >= 0; i-- {
		if e.source[i] == '\n' {
			return uint(i + 1)
		}
	}
	return 0
}
