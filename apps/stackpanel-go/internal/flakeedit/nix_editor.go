package flakeedit

import (
	"errors"
	"fmt"
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// NixEditor performs source-preserving edits on Nix attribute sets. It operates
// on the "editable attrset" - the last top-level attrset in the file, which
// handles both bare attrsets and function-wrapped ones (e.g. { config, ... }: { ... }).
type NixEditor struct {
	source []byte
	tree   *tree_sitter.Tree
	parser *tree_sitter.Parser
}

// NewNixEditor parses a Nix source and returns an editor.
// The caller must call Close() when done.
func NewNixEditor(source []byte) (*NixEditor, error) {
	parser, tree, err := newParserAndTree(source)
	if err != nil {
		return nil, err
	}

	return &NixEditor{source: source, tree: tree, parser: parser}, nil
}

// Close releases parser/tree-sitter resources.
func (e *NixEditor) Close() {
	if e.tree != nil {
		e.tree.Close()
	}
	if e.parser != nil {
		e.parser.Close()
	}
}

// PatchNixPath is a convenience wrapper that parses, patches, and returns in one call.
// valueExpr is raw Nix source (e.g. `"hello"`, `true`, `{ foo = 1; }`).
func PatchNixPath(source []byte, path []string, valueExpr string) ([]byte, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()

	return editor.PatchPath(path, valueExpr)
}

// DeleteNixPath removes the binding at the provided dotted path.
func DeleteNixPath(source []byte, path []string) ([]byte, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()

	return editor.DeletePath(path)
}

// ReplaceNixEditableAttrset replaces the entire editable attrset body with new source.
// If the file has a function wrapper (e.g. { config, ... }: { ... }), only the inner
// attrset is replaced - the wrapper and its arguments are preserved.
func ReplaceNixEditableAttrset(source []byte, attrsetExpr string) ([]byte, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()

	return editor.ReplaceEditableAttrset(attrsetExpr)
}

// ImportTargetForTopLevelBinding inspects the editable attrset and, if its
// binding for attrName has the form `attrName = import <path> ...;` (i.e. the
// value delegates to another file), returns the unquoted path string. Used by
// callers that need to redirect writes from a delegating file (e.g.
// .stack/config.nix `apps = import ./config.apps.nix args;`) into the actual
// data file. Returns ("", false, nil) when the binding is missing or its value
// is not an import expression.
func ImportTargetForTopLevelBinding(source []byte, attrName string) (string, bool, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return "", false, err
	}
	defer editor.Close()

	root := editor.findEditableAttrset()
	if root == nil {
		return "", false, nil
	}

	binding, matched, valueNode := editor.findBestBinding(root, []string{attrName})
	if binding == nil || len(matched) != 1 || valueNode == nil {
		return "", false, nil
	}

	target, ok := parseImportTarget(editor.nodeText(valueNode))
	return target, ok, nil
}

// ExtractAppVariableLinksFromSource scans raw app config source for env
// bindings that reference global variables (config.variables."<id>".value)
// and returns a nested map: appID -> envName -> envKey -> variableID.
func ExtractAppVariableLinksFromSource(source []byte) (map[string]map[string]map[string]string, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()

	return editor.ExtractAppVariableLinks(), nil
}

// PatchPath sets a value expression at the requested dotted path.
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

// DeletePath removes the binding at the provided dotted path.
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

// ReplaceEditableAttrset replaces the located editable root attrset body.
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
	appsNode := e.findAttrsetAtPath([]string{"apps"})
	if appsNode == nil {
		root := e.findEditableAttrset()
		if root == nil || !e.looksLikeAppsAttrset(root) {
			return map[string]map[string]map[string]string{}
		}
		appsNode = root
	}

	return e.extractAppVariableLinksFromAppsAttrset(appsNode)
}

func (e *NixEditor) looksLikeAppsAttrset(attrset *tree_sitter.Node) bool {
	for _, binding := range e.bindings(attrset) {
		if len(e.bindingAttrpath(binding)) != 1 {
			continue
		}
		appAttrset := e.bindingAttrsetValue(binding)
		if appAttrset == nil {
			continue
		}
		if e.findAttrsetWithin(appAttrset, []string{"environments"}) != nil ||
			e.findAttrsetWithin(appAttrset, []string{"env"}) != nil {
			return true
		}
	}

	return false
}

func (e *NixEditor) extractAppVariableLinksFromAppsAttrset(appsNode *tree_sitter.Node) map[string]map[string]map[string]string {
	links := make(map[string]map[string]map[string]string)

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

		appEnvironments := e.appEnvironmentIDs(appAttrset)
		e.extractAppEnvVariableLinks(links, appID, appEnvironments, appAttrset)
		e.extractLegacyAppEnvironmentLinks(links, appID, appAttrset)
	}

	return links
}

func (e *NixEditor) extractLegacyAppEnvironmentLinks(
	links map[string]map[string]map[string]string,
	appID string,
	appAttrset *tree_sitter.Node,
) {
	envsNode := e.findAttrsetWithin(appAttrset, []string{"environments"})
	if envsNode == nil {
		return
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

			e.setAppVariableLink(links, appID, envName, envKey, variableID)
		}
	}
}

func (e *NixEditor) extractAppEnvVariableLinks(
	links map[string]map[string]map[string]string,
	appID string,
	envNames []string,
	appAttrset *tree_sitter.Node,
) {
	envNode := e.findAttrsetWithin(appAttrset, []string{"env"})
	if envNode == nil {
		return
	}

	for _, envVarBinding := range e.bindings(envNode) {
		envKeyPath := e.bindingAttrpath(envVarBinding)
		if len(envKeyPath) != 1 {
			continue
		}

		envKey := envKeyPath[0]
		envVarAttrset := e.bindingAttrsetValue(envVarBinding)
		if envVarAttrset == nil {
			continue
		}

		valueBinding, matched, valueNode := e.findBestBinding(envVarAttrset, []string{"value"})
		if valueBinding == nil || len(matched) != 1 || valueNode == nil {
			continue
		}

		variableID, ok := parseConfigVariableExpr(e.nodeText(valueNode))
		if !ok {
			continue
		}

		for _, envName := range envNames {
			e.setAppVariableLink(links, appID, envName, envKey, variableID)
		}
	}
}

func (e *NixEditor) appEnvironmentIDs(appAttrset *tree_sitter.Node) []string {
	for _, path := range [][]string{
		{"environmentIds"},
		{"environment-ids"},
	} {
		binding, matched, valueNode := e.findBestBinding(appAttrset, path)
		if binding == nil || len(matched) != 1 || valueNode == nil {
			continue
		}

		rawNames := parseNixStringList(e.nodeText(valueNode))
		if len(rawNames) == 0 {
			continue
		}

		names := make([]string, 0, len(rawNames))
		for _, rawName := range rawNames {
			name := strings.TrimSpace(rawName)
			if name == "" {
				continue
			}
			if name == "production" {
				name = "prod"
			} else if name == "development" {
				name = "dev"
			}
			names = append(names, name)
		}
		if len(names) > 0 {
			return uniqueStrings(names)
		}
	}

	return []string{"dev", "prod", "staging", "test"}
}

func uniqueStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}

func (e *NixEditor) setAppVariableLink(
	links map[string]map[string]map[string]string,
	appID string,
	envName string,
	envKey string,
	variableID string,
) {
	if links[appID] == nil {
		links[appID] = make(map[string]map[string]string)
	}
	if links[appID][envName] == nil {
		links[appID][envName] = make(map[string]string)
	}

	links[appID][envName][envKey] = variableID
}

// patchWithinAttrset recursively descends into nested attrsets to find the target
// path. If the path doesn't exist, it inserts a new binding before the closing brace.
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

// buildNestedBinding renders a multi-segment path as nested Nix attrset bindings.
// For example, path=["a","b"] value="1" becomes:
//
//	a = {
//	  b = 1;
//	};
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
