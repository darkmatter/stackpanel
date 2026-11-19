package flakeedit

import (
	"errors"
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
func ImportTargetForTopLevelBinding(
	source []byte,
	attrName string,
) (string, bool, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return "", false, err
	}
	defer editor.Close()
	if editor.tree.RootNode().HasError() {
		return "", false, errors.New("cannot resolve import in malformed Nix source")
	}

	root := editor.resultAttrset()
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
func ExtractAppVariableLinksFromSource(
	source []byte,
) (map[string]map[string]map[string]string, error) {
	editor, err := NewNixEditor(source)
	if err != nil {
		return nil, err
	}
	defer editor.Close()

	return editor.ExtractAppVariableLinks(), nil
}

// PatchPath sets a value expression at the requested dotted path.
func (e *NixEditor) PatchPath(path []string, valueExpr string) ([]byte, error) {
	if e.tree.RootNode().HasError() {
		return nil, errors.New("cannot patch Nix source containing syntax errors")
	}
	if len(path) == 0 {
		return nil, errors.New("path is required")
	}

	root := e.resultAttrset()
	if root == nil {
		return nil, errors.New("could not find editable attrset")
	}

	return e.checked(e.patchWithinAttrset(root, path, valueExpr))
}

// DeletePath removes the binding at the provided dotted path.
func (e *NixEditor) DeletePath(path []string) ([]byte, error) {
	if e.tree.RootNode().HasError() {
		return nil, errors.New("cannot delete from Nix source containing syntax errors")
	}
	if len(path) == 0 {
		return nil, errors.New("path is required")
	}

	root := e.resultAttrset()
	if root == nil {
		return nil, errors.New("could not find editable attrset")
	}

	ast := FlakeEditor{source: e.source, tree: e.tree, parser: e.parser}
	return e.checked(ast.removeAttr(root, path))
}

// HasTopLevelBinding reports whether a literal result set (possibly inside a
// module function) binds key or any of its descendants in dotted notation.
// Unknown/dynamic declarations are errors rather than permission to shadow.
func HasTopLevelBinding(source []byte, key string) (bool, error) {
	e, err := NewNixEditor(source)
	if err != nil {
		return false, err
	}
	defer e.Close()
	if e.tree.RootNode().HasError() {
		return false, errors.New("cannot inspect malformed Nix source")
	}
	ast := FlakeEditor{source: source}
	loc, err := ast.locateAttr(e.resultAttrset(), []string{key})
	return err == nil && len(loc.defs) != 0, err
}

// Only mutate the expression returned to the caller. An arbitrary descendant
// attrset (e.g. a function argument or one branch of an if) isn't the config.
func (e *NixEditor) resultAttrset() *tree_sitter.Node {
	for n := e.tree.RootNode().ChildByFieldName("expression"); n != nil; {
		switch n.Kind() {
		case "attrset_expression":
			return n
		case "function_expression",
			"let_expression",
			"with_expression",
			"assert_expression":
			n = n.ChildByFieldName("body")
		case "parenthesized_expression":
			n = n.ChildByFieldName("expression")
		default:
			return nil
		}
	}
	return nil
}

// ReplaceEditableAttrset replaces the located editable root attrset body.
func (e *NixEditor) ReplaceEditableAttrset(attrsetExpr string) ([]byte, error) {
	root := e.findEditableAttrset()
	if root == nil {
		return nil, errors.New("could not find editable attrset")
	}

	replaceEnd := root.EndByte()
	if strings.HasSuffix(attrsetExpr, "\n") && replaceEnd < uint(len(e.source)) &&
		e.source[replaceEnd] == '\n' {
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

func (e *NixEditor) extractAppVariableLinksFromAppsAttrset(
	appsNode *tree_sitter.Node,
) map[string]map[string]map[string]string {
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

		valueBinding, matched, valueNode := e.findBestBinding(
			envVarAttrset,
			[]string{"value"},
		)
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
func (e *NixEditor) patchWithinAttrset(
	attrset *tree_sitter.Node,
	path []string,
	valueExpr string,
) ([]byte, error) {
	ast := FlakeEditor{source: e.source}
	_, value, container, rest, err := ast.lookupAttr(attrset, path)
	if err != nil {
		return nil, err
	}
	if value != nil {
		return replaceRange(
			e.source,
			value.StartByte(),
			value.EndByte(),
			[]byte(valueExpr),
		), nil
	}
	attrset, path = container, rest

	closingBrace := e.findClosingBrace(attrset)
	if closingBrace == nil {
		return nil, errors.New("could not find closing brace for attrset")
	}

	// When a sibling already defines a leaf under path[0] via dotted notation
	// (e.g. `ide.zed.enable = true;`), a fresh nested `ide = { ... };` block would
	// duplicate the `ide` attribute and break the file. Insert in dotted form so
	// the new binding merges with the existing sibling instead of overwriting it.
	indent := e.detectBindingIndent(attrset)
	var insertText string
	if e.hasSiblingPrefixCollision(attrset, path) {
		insertText = e.buildDottedBinding(indent, path, valueExpr)
	} else {
		insertText = e.buildNestedBinding(indent, path, valueExpr)
	}
	insertPos := e.startOfLine(closingBrace.StartByte())
	if strings.TrimSpace(string(e.source[insertPos:closingBrace.StartByte()])) != "" {
		insertPos = closingBrace.StartByte()
		insertText = "\n" + insertText + strings.Repeat(
			" ",
			e.lineIndent(attrset.StartByte()),
		)
	}

	return insertAt(e.source, insertPos, []byte(insertText)), nil
}

func (e *NixEditor) checked(source []byte, err error) ([]byte, error) {
	if err != nil {
		return nil, err
	}
	tree := e.parser.Parse(source, nil)
	if tree == nil {
		return nil, errors.New("could not parse edited Nix source")
	}
	defer tree.Close()
	if tree.RootNode().HasError() {
		return nil, errors.New("edit would produce invalid Nix source")
	}
	return source, nil
}

// buildNestedBinding renders a multi-segment path as nested Nix attrset bindings.
// For example, path=["a","b"] value="1" becomes:
//
//	a = {
//	  b = 1;
//	};
func (e *NixEditor) buildNestedBinding(
	baseIndent string,
	path []string,
	valueExpr string,
) string {
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
