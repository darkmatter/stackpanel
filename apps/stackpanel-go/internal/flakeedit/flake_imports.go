package flakeedit

import (
	"bytes"
	"errors"
	"fmt"
	"slices"
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// importPath is relative to one input; only registry installs may leave
// the default output to the consumer's automatic discovery.
func (e *FlakeEditor) editModuleImport(
	name, importPath string,
	remove, forceExplicit bool,
) ([]byte, error) {
	if !validIdent(name) || name == "self" || name == "stackpanel" {
		return nil, fmt.Errorf("invalid module input %q", name)
	}
	if importPath == "" {
		importPath = "stackpanelModules.default"
	}
	path, err := e.parseImportPath(importPath)
	if err != nil {
		return nil, err
	}
	if path[0] == "inputs" {
		return nil, errors.New("module import path must be relative to its input")
	}
	return e.editImport(name, path, remove, !forceExplicit)
}

// Fast path for registry slugs. For quoted keys use the Nix grammar rather
// than splitting on dots inside strings or applying Go string escape rules.
func (e *FlakeEditor) parseImportPath(raw string) ([]string, error) {
	if path := strings.Split(
		raw,
		".",
	); !slices.ContainsFunc(
		path,
		func(s string) bool { return !validIdent(s) },
	) {
		return path, nil
	}
	invalid := fmt.Errorf("expected a static attribute path, got %q", raw)
	if raw == "" || strings.IndexByte(raw, 0) >= 0 {
		return nil, invalid
	}
	raw = "_input." + raw // selection grammar permits a quoted first attribute
	src := []byte(raw)
	tree := e.parser.Parse(src, nil)
	if tree == nil {
		return nil, invalid
	}
	defer tree.Close()
	root := tree.RootNode()
	n := root.ChildByFieldName("expression")
	if root.HasError() || n == nil || n.Kind() != "select_expression" ||
		n.StartByte() != 0 ||
		n.EndByte() != uint(len(src)) {
		return nil, invalid
	}
	base := n.ChildByFieldName("expression")
	attrs := n.ChildByFieldName("attrpath")
	if base.Kind() != "variable_expression" || n.ChildByFieldName("default") != nil ||
		e.findChildByKind(n, "comment") != nil {
		return nil, invalid
	}
	view := FlakeEditor{source: src}
	var path []string
	for i := uint(0); i < attrs.NamedChildCount(); i++ {
		segment, ok := view.attrSegment(attrs.NamedChild(i))
		if !ok {
			return nil, invalid
		}
		path = append(path, segment)
	}
	return path, nil
}

var quoteImportKey = strings.NewReplacer(
	`\`,
	`\\`,
	`"`,
	`\"`,
	"${",
	`\${`,
	"\r",
	`\r`,
	"\n",
	`\n`,
	"\t",
	`\t`,
)

func renderImportPath(path []string) string {
	// The first component is a bound variable, never an attribute literal.
	for i, segment := range path[1:] {
		if !validIdent(segment) {
			path[i+1] = `"` + quoteImportKey.Replace(segment) + `"`
		}
	}
	return strings.Join(path, ".")
}

// ModuleImportPath returns the input-relative export to validate for a local
// override. A unique explicit import takes precedence over auto-discovery.
// This inspects the consumer's syntax; it does not evaluate the export or
// prove the project's effective configuration enables the module.
func (e *FlakeEditor) ModuleImportPath(name string) (string, error) {
	if !validIdent(name) || name == "stackpanel" || name == "self" {
		return "", fmt.Errorf("invalid module input %q", name)
	}
	site, err := e.importTarget()
	if err != nil {
		return "", err
	}
	list, _, _, err := e.importList(site)
	if err != nil {
		return "", err
	}
	var selected string
	for i := uint(0); list != nil && i < list.NamedChildCount(); i++ {
		n := importUnparen(list.NamedChild(i))
		switch n.Kind() {
		case "comment", "attrset_expression", "function_expression":
			continue
		case "path_expression":
			if e.findChildByKind(n, "interpolation") == nil {
				continue
			}
		}
		p := site.scope.relative(e.importSelection(n))
		if len(p) == 0 {
			return "", errors.New("cannot identify input behind computed Stackpanel import")
		}
		if p[0] != name {
			continue
		}
		if len(p) == 1 {
			return "", fmt.Errorf("expected an export of input %q", name)
		}
		output := strings.TrimPrefix(renderImportPath(p), name+".")
		if selected != "" && selected != output {
			return "", fmt.Errorf("ambiguous module exports for %q", name)
		}
		selected = output
	}
	if selected != "" {
		return selected, nil
	}
	auto, err := e.autoImports(site)
	if err != nil {
		return "", err
	}
	if auto && site.forwardedInputs && e.HasInput(name) {
		return "stackpanelModules.default", nil
	}
	return "", fmt.Errorf("no module import found for input %q", name)
}

type importForm int

const (
	stackpanelCall importForm = iota
	flakePartsCall
)

type importSite struct {
	form            importForm
	set             *tree_sitter.Node
	scope           importScope
	forwardedInputs bool
}

// Keep track of *where* a name comes from. Merely finding the string "inputs"
// somewhere in the outputs expression says nothing about its lexical binding.
type importBinding int

const (
	localBinding importBinding = iota + 1
	namedInput
	allInputs
)

type importScope map[string]importBinding

func (s importScope) relative(path []string) []string {
	if len(path) == 0 {
		return nil
	}
	switch s[path[0]] {
	case allInputs:
		return path[1:]
	case namedInput:
		return path
	}
	return nil
}

func (s importScope) modulePath(name string, output []string) ([]string, error) {
	// Prefer the outputs alias over a destructured input. If flake-parts
	// also passes its inputs argument to a module lambda, prefer that name.
	if s["inputs"] == allInputs {
		return append([]string{"inputs", name}, output...), nil
	}
	for alias, role := range s {
		if role == allInputs {
			return append([]string{alias, name}, output...), nil
		}
	}
	if s[name] == namedInput {
		return append([]string{name}, output...), nil
	}
	return nil, fmt.Errorf(
		"input %q is not in scope; bind the outputs argument with @inputs",
		name,
	)
}

func importUnparen(n *tree_sitter.Node) *tree_sitter.Node {
	for n != nil && n.Kind() == "parenthesized_expression" {
		n = n.ChildByFieldName("expression")
	}
	return n
}

// Return segments, not source text: parentheses, spacing, literal quotes and
// comments between segments do not change a Nix selection's identity.
func (e *FlakeEditor) importSelection(n *tree_sitter.Node) []string {
	n = importUnparen(n)
	if n == nil {
		return nil
	}
	switch n.Kind() {
	case "variable_expression":
		return []string{e.nodeText(n.ChildByFieldName("name"))}
	case "select_expression":
		if n.ChildByFieldName("default") != nil {
			return nil
		}
		path := e.importSelection(n.ChildByFieldName("expression"))
		if len(path) == 0 {
			return nil
		}
		attrs := n.ChildByFieldName("attrpath")
		for i := uint(0); i < attrs.NamedChildCount(); i++ {
			a := attrs.NamedChild(i)
			if a.Kind() == "comment" {
				continue
			}
			name, ok := e.attrSegment(a)
			if !ok {
				return nil
			}
			path = append(path, name)
		}
		return path
	}
	return nil
}

// Visit directly bound names only. A let is recursive, so its bindings
// shadow the enclosing outputs arguments in both its body and its RHSs.
func (e *FlakeEditor) importBindings(
	n *tree_sitter.Node,
	visit func(string, *tree_sitter.Node, bool),
) error {
	bs := e.findChildByKind(n, "binding_set")
	if bs == nil {
		return nil
	}
	for i := uint(0); i < bs.NamedChildCount(); i++ {
		b := bs.NamedChild(i)
		if b.Kind() == "comment" {
			continue
		}
		attrs := b.ChildByFieldName("attrs")
		if b.Kind() == "binding" {
			attrs = b.ChildByFieldName("attrpath")
		}
		if attrs == nil {
			return errors.New("unsupported declaration in import scope")
		}
		for j := uint(0); j < attrs.NamedChildCount(); j++ {
			key := attrs.NamedChild(j)
			if key.Kind() == "comment" {
				continue
			}
			name, ok := e.attrSegment(key)
			if !ok {
				return errors.New("computed attribute in import scope")
			}
			visit(name, b, b.Kind() == "binding" && e.findChildByKind(attrs, ".") != nil)
			if b.Kind() == "binding" {
				break
			}
		}
	}
	return nil
}

// Auto-discovery (and flake-parts' module argument named inputs) is only
// meaningful when the caller forwards the actual, unmodified outputs inputs.
func (e *FlakeEditor) forwardsImportInputs(
	set *tree_sitter.Node,
	scope importScope,
) bool {
	count, forwarded := 0, false
	err := e.importBindings(set, func(name string, b *tree_sitter.Node, dotted bool) {
		if name != "inputs" {
			return
		}
		count++
		switch b.Kind() {
		case "inherit":
			forwarded = scope[name] == allInputs
		case "binding":
			p := e.importSelection(b.ChildByFieldName("expression"))
			forwarded = !dotted && len(p) == 1 && scope[p[0]] == allInputs
		}
	})
	return err == nil && count == 1 && forwarded
}

// For an outputs lambda its formals are the named inputs. In an inner
// module lambda they are ordinary module arguments (only inputs is special).
func (e *FlakeEditor) bindImportArgs(
	fn *tree_sitter.Node,
	scope importScope,
	outputs, forwarded bool,
) error {
	bound := make(map[string]bool)
	if u := fn.ChildByFieldName("universal"); u != nil {
		name := e.nodeText(u)
		bound[name] = true
		scope[name] = localBinding
		if outputs {
			scope[name] = allInputs
		}
	}
	args := fn.ChildByFieldName("formals")
	if args == nil {
		return nil
	}
	for i := uint(0); i < args.NamedChildCount(); i++ {
		f := args.NamedChild(i)
		if f.Kind() != "formal" {
			continue
		}
		name := e.nodeText(f.ChildByFieldName("name"))
		if bound[name] {
			return fmt.Errorf("duplicate function parameter %q", name)
		}
		bound[name] = true
		switch {
		case outputs:
			scope[name] = namedInput
		case name == "inputs" && forwarded:
			scope[name] = allInputs
		default:
			scope[name] = localBinding
		}
	}
	return nil
}

func (e *FlakeEditor) importTarget() (*importSite, error) {
	if e.HasParseErrors() {
		return nil, errors.New("cannot edit imports: flake.nix has syntax errors")
	}
	root := e.tree.RootNode()
	_, outputs, _, _, err := e.lookupAttr(
		e.findChildByKind(root, "attrset_expression"),
		[]string{"outputs"},
	)
	if err != nil {
		return nil, err
	}
	fn := importUnparen(outputs)
	if fn == nil || fn.Kind() != "function_expression" {
		return nil, errors.New("expected a flake outputs function")
	}
	scope := make(importScope)
	if err := e.bindImportArgs(fn, scope, true, false); err != nil {
		return nil, err
	}
	n := importUnparen(fn.ChildByFieldName("body"))
	unsupported := errors.New(
		"unsupported outputs: expected stackpanel.lib.mkFlake or a stackpanel flake-parts module",
	)
	// Only follow the outputs body, never arbitrary descendant bindings.
	for {
		switch n.Kind() {
		case "assert_expression":
			n = importUnparen(n.ChildByFieldName("body"))
			continue
		case "let_expression":
			if err := e.importBindings(
				n,
				func(name string, _ *tree_sitter.Node, _ bool) { scope[name] = localBinding },
			); err != nil {
				return nil, err
			}
			n = importUnparen(n.ChildByFieldName("body"))
			continue
		case "apply_expression":
			callee := importUnparen(n.ChildByFieldName("function"))
			arg := importUnparen(n.ChildByFieldName("argument"))
			which := scope.relative(e.importSelection(callee))
			if slices.Equal(which, []string{"stackpanel", "lib", "mkFlake"}) &&
				arg.Kind() == "attrset_expression" {
				return &importSite{
					stackpanelCall,
					arg,
					scope,
					e.forwardsImportInputs(arg, scope),
				}, nil
			}
			if callee.Kind() == "apply_expression" {
				which = scope.relative(e.importSelection(callee.ChildByFieldName("function")))
				if slices.Equal(which, []string{"flake-parts", "lib", "mkFlake"}) {
					options := importUnparen(callee.ChildByFieldName("argument"))
					if options.Kind() != "attrset_expression" {
						return nil, errors.New(
							"expected literal options for flake-parts.lib.mkFlake",
						)
					}
					forwarded := e.forwardsImportInputs(options, scope)
					if arg.Kind() == "function_expression" {
						if err := e.bindImportArgs(arg, scope, false, forwarded); err != nil {
							return nil, err
						}
						arg = importUnparen(arg.ChildByFieldName("body"))
					}
					if arg.Kind() != "attrset_expression" {
						return nil, errors.New("expected a literal flake-parts module body")
					}
					return &importSite{flakePartsCall, arg, scope, forwarded}, nil
				}
			}
		}
		return nil, unsupported
	}
}

// Choose one Stackpanel list, never flake-parts' own `imports`. If there is
// no option yet in a flake-parts module, require positive evidence that it
// actually imports Stackpanel before introducing a new option.
func (e *FlakeEditor) importList(
	site *importSite,
) (list, container *tree_sitter.Node, key []string, err error) {
	_, list, container, key, err = e.lookupAttr(site.set, []string{"stackpanel", "imports"})
	if err != nil {
		return
	}
	if site.form == stackpanelCall {
		_, argument, set, path, lookupErr := e.lookupAttr(
			site.set,
			[]string{"stackpanelImports"},
		)
		if lookupErr != nil {
			return nil, nil, nil, lookupErr
		}
		if list != nil && argument != nil {
			return nil, nil, nil, errors.New(
				"ambiguous import target: both stackpanelImports and stackpanel.imports exist",
			)
		}
		if list == nil {
			list, container, key = argument, set, path
		}
	} else if list == nil {
		_, imports, _, _, lookupErr := e.lookupAttr(site.set, []string{"imports"})
		if lookupErr != nil {
			return nil, nil, nil, lookupErr
		}
		imports = importUnparen(imports)
		found := false
		if imports != nil && imports.Kind() == "list_expression" {
			for i := uint(0); i < imports.NamedChildCount(); i++ {
				if slices.Equal(
					site.scope.relative(e.importSelection(imports.NamedChild(i))),
					[]string{"stackpanel", "flakeModules", "default"},
				) {
					found = true
					break
				}
			}
		}
		if !found {
			return nil, nil, nil, errors.New(
				"no stackpanel.imports or stackpanel.flakeModules.default in flake-parts module",
			)
		}
	}
	list = importUnparen(list)
	if list != nil && list.Kind() != "list_expression" {
		return nil, nil, nil, errors.New("expected a literal Stackpanel imports list")
	}
	return
}

func (e *FlakeEditor) autoImports(site *importSite) (bool, error) {
	// The nested module option takes precedence over mkFlake's mkDefault.
	for _, path := range [][]string{{"stackpanel", "autoImportInputs"}, {"autoImportInputs"}} {
		_, v, _, _, err := e.lookupAttr(site.set, path)
		if err != nil {
			return false, err
		}
		if v == nil {
			continue
		}
		flag := e.nodeText(importUnparen(v))
		if site.scope[flag] != 0 {
			return false, errors.New("autoImportInputs is not a literal boolean")
		}
		switch flag {
		case "true":
			return true, nil
		case "false":
			return false, nil
		}
		return false, errors.New("expected a literal boolean for autoImportInputs")
	}
	return true, nil
}

func (e *FlakeEditor) editImport(
	name string,
	path []string,
	remove, allowDiscovery bool,
) ([]byte, error) {
	site, err := e.importTarget()
	if err != nil {
		return nil, err
	}
	list, set, key, err := e.importList(site)
	if err != nil {
		return nil, err
	}
	mayDiscover := allowDiscovery && site.form == stackpanelCall &&
		slices.Equal(path, []string{"stackpanelModules", "default"})
	path, err = site.scope.modulePath(name, path)
	if err != nil {
		return nil, err
	}
	want := site.scope.relative(path)
	var matches []*tree_sitter.Node
	for i := uint(0); list != nil && i < list.NamedChildCount(); i++ {
		item := list.NamedChild(i)
		if item.Kind() == "comment" {
			continue
		}
		p := e.importSelection(item)
		if len(p) > 0 && site.scope[p[0]] == 0 {
			return nil, fmt.Errorf("unbound import reference %q", p[0])
		}
		if slices.Equal(path, p) ||
			len(want) > 0 && slices.Equal(want, site.scope.relative(p)) {
			matches = append(matches, item)
		} else if p == nil {
			// Literal local paths and inline Nix modules can coexist with
			// input references. Do not guess the result of a computed item.
			switch importUnparen(item).Kind() {
			case "path_expression":
				if e.findChildByKind(importUnparen(item), "interpolation") != nil {
					return nil, errors.New("computed path in Stackpanel imports")
				}
			case "attrset_expression", "function_expression":
			default:
				return nil, errors.New("computed list item in Stackpanel imports")
			}
		}
	}
	if remove {
		return e.removeNodes(matches...), nil
	}
	if len(matches) > 0 {
		return e.source, nil
	}
	if mayDiscover {
		auto, err := e.autoImports(site)
		if err != nil {
			return nil, err
		}
		if auto {
			if !site.forwardedInputs {
				return nil, errors.New(
					"auto-import requires mkFlake to forward the outputs inputs",
				)
			}
			return e.source, nil
		}
	}
	expr := renderImportPath(path)
	if list == nil {
		return e.appendAttr(set, strings.Join(key, ".")+" = [ "+expr+" ];"), nil
	}
	return e.appendImportItem(list, expr), nil
}

func (e *FlakeEditor) appendImportItem(list *tree_sitter.Node, expr string) []byte {
	end := list.EndByte() - 1 // literal, parse-checked `]`
	start := uint(bytes.LastIndexByte(e.source[:end], '\n') + 1)
	prefix := e.source[start:end]
	if len(bytes.Trim(prefix, " \t")) > 0 {
		if end > 0 && e.source[end-1] != ' ' && e.source[end-1] != '\t' {
			expr = " " + expr
		}
		return insertAt(e.source, end, []byte(expr+" "))
	}
	indent := string(prefix) + "  "
	for i := uint(0); i < list.NamedChildCount(); i++ {
		pos := list.NamedChild(i).StartByte()
		line := uint(bytes.LastIndexByte(e.source[:pos], '\n') + 1)
		if p := e.source[line:pos]; len(bytes.Trim(p, " \t")) == 0 {
			indent = string(p)
			break
		}
	}
	return insertAt(e.source, start, []byte(indent+expr+"\n"))
}
