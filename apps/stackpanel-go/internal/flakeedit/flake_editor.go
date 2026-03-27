package flakeedit

import (
	"bytes"
	"errors"
	"fmt"
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// FlakeEditor provides flake.nix-specific editing operations built on tree-sitter.
// Unlike NixEditor (which targets any Nix attrset), FlakeEditor understands flake
// structure: the top-level { inputs, outputs } shape and the stackpanelImports list.
type FlakeEditor struct {
	source []byte
	tree   *tree_sitter.Tree
	parser *tree_sitter.Parser
}

// NewFlakeEditor parses a flake.nix source and returns a reusable editor.
// The caller must call Close() once finished.
func NewFlakeEditor(source []byte) (*FlakeEditor, error) {
	parser, tree, err := newParserAndTree(source)
	if err != nil {
		return nil, err
	}

	root := tree.RootNode()
	if root.HasError() {
		// tree-sitter may still provide a best-effort tree for incomplete files,
		// so we keep editing support while surfacing syntax quality via
		// HasParseErrors().
	}

	return &FlakeEditor{source: source, tree: tree, parser: parser}, nil
}

// Close releases parser/tree-sitter resources.
func (e *FlakeEditor) Close() {
	if e.tree != nil {
		e.tree.Close()
	}
	if e.parser != nil {
		e.parser.Close()
	}
}

// HasParseErrors reports whether the current parsed tree contains syntax errors.
func (e *FlakeEditor) HasParseErrors() bool {
	return e.tree.RootNode().HasError()
}

// HasInput checks whether an input named `name` already exists under
// `inputs = { ... }`.
func (e *FlakeEditor) HasInput(name string) bool {
	inputsNode := e.findInputsAttrset()
	if inputsNode == nil {
		return false
	}
	return e.findInputBinding(inputsNode, name) != nil
}

// AddInput inserts a new input declaration in `inputs = { ... }`.
// Returns unchanged source if the input already exists.
//
// Uses dot notation rather than nested attrsets so the insertion is a simple
// line append that doesn't interact with tree-sitter node boundaries:
//
//	<name>.url = "github:author/repo";
//	<name>.inputs.nixpkgs.follows = "nixpkgs";
func (e *FlakeEditor) AddInput(input FlakeInput) ([]byte, error) {
	inputsNode := e.findInputsAttrset()
	if inputsNode == nil {
		return nil, errors.New("could not find `inputs = { ... }` block in flake.nix")
	}

	if e.findInputBinding(inputsNode, input.Name) != nil {
		return e.source, nil
	}

	closingBrace := e.findClosingBrace(inputsNode)
	if closingBrace == nil {
		return nil, errors.New("could not find closing `}` of inputs block")
	}

	indent := e.detectBindingIndent(inputsNode)

	var lines []string
	lines = append(lines, fmt.Sprintf("%s%s.url = %q;", indent, input.Name, input.URL))
	if input.FollowsNixpkgs {
		lines = append(lines, fmt.Sprintf("%s%s.inputs.nixpkgs.follows = \"nixpkgs\";", indent, input.Name))
	}

	insertText := strings.Join(lines, "\n") + "\n"
	insertPos := e.startOfLine(closingBrace.StartByte())
	modified := insertAt(e.source, insertPos, []byte(insertText))

	return modified, nil
}

// AddStackpanelImport inserts an import expression in `stackpanelImports = [...]`.
func (e *FlakeEditor) AddStackpanelImport(importExpr string) ([]byte, error) {
	listNode := e.findStackpanelImportsList()
	if listNode == nil {
		return nil, errors.New("could not find `stackpanelImports = [ ... ]` in flake.nix")
	}

	if e.listContainsExpr(listNode, importExpr) {
		return e.source, nil
	}

	closingBracket := e.findClosingBracket(listNode)
	if closingBracket == nil {
		return nil, errors.New("could not find closing `]` of stackpanelImports list")
	}

	openBracket := e.findOpenBracket(listNode)
	if openBracket == nil {
		return nil, errors.New("could not find opening `[` of stackpanelImports list")
	}

	var insertText string
	if openBracket.StartPosition().Row == closingBracket.StartPosition().Row {
		// Single-line list: preserve list formatting by inserting before `]`.
		insertText = importExpr + " "
	} else {
		indent := e.detectListItemIndent(listNode)
		insertText = indent + importExpr + "\n"
	}

	insertPos := closingBracket.StartByte()
	modified := insertAt(e.source, insertPos, []byte(insertText))

	return modified, nil
}

// AddInputAndImport is the primary high-level operation: it adds a flake input
// AND the corresponding import expression in one call. The tree is re-parsed
// between the two edits so byte offsets remain accurate.
func (e *FlakeEditor) AddInputAndImport(input FlakeInput, importExpr string) (*EditResult, error) {
	result := &EditResult{}

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

		// Re-parse is required because AddInput shifted byte offsets. Without this,
		// the import insertion would write to the wrong position.
		e.tree.Close()
		e.tree = e.parser.Parse(modified, nil)
		if e.tree == nil {
			return nil, errors.New("failed to re-parse after adding input")
		}
		e.source = modified
	}

	if importExpr != "" {
		modified, err := e.AddStackpanelImport(importExpr)
		if err != nil {
			// Some flakes omit `stackpanelImports`; treat that as non-fatal.
			result.Modified = e.source
			return result, nil
		}

		if !bytes.Equal(modified, e.source) {
			result.ImportAdded = true
		}
		result.Modified = modified
		e.source = modified
	}

	return result, nil
}
