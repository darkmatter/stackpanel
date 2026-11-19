package flakeedit

import (
	"bytes"
	"errors"
	"fmt"
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// FlakeEditor edits a literal flake attrset without reprinting the document.
// Close it when done. Individual source edits return new bytes; rejected
// multi-step edits never leave a partially changed tree in the caller.
type FlakeEditor struct {
	source []byte
	tree   *tree_sitter.Tree
	parser *tree_sitter.Parser
}

func NewFlakeEditor(source []byte) (*FlakeEditor, error) {
	parser, tree, err := newParserAndTree(source)
	if err != nil {
		return nil, err
	}
	return &FlakeEditor{source: source, tree: tree, parser: parser}, nil
}

func (e *FlakeEditor) Close() {
	e.tree.Close()
	e.parser.Close()
}

func (e *FlakeEditor) HasParseErrors() bool { return e.tree.RootNode().HasError() }

func (e *FlakeEditor) editable() error {
	if e.HasParseErrors() {
		return errors.New("flake.nix contains syntax errors; refusing to edit")
	}
	if e.rootSet() == nil {
		return errors.New("expected a literal top-level flake attribute set")
	}
	return nil
}

// apply advances a private working tree. All later node offsets refer to the
// new bytes. Even the last edit is checked before its bytes can reach disk.
func (e *FlakeEditor) apply(src []byte, err error) error {
	if err != nil || bytes.Equal(src, e.source) {
		return err
	}
	tree := e.parser.Parse(src, nil)
	if tree == nil {
		return errors.New("failed to parse modified flake.nix")
	}
	if tree.RootNode().HasError() {
		tree.Close()
		return errors.New("edit would produce invalid flake.nix")
	}
	e.tree.Close()
	e.source, e.tree = src, tree
	return nil
}

func (e *FlakeEditor) transaction(edit func(*FlakeEditor) error) ([]byte, error) {
	if err := e.editable(); err != nil {
		return nil, err
	}
	w := &FlakeEditor{e.source, e.tree.Clone(), e.parser}
	defer func() { w.tree.Close() }()
	if err := edit(w); err != nil {
		return nil, err
	}
	return w.source, nil
}

func (e *FlakeEditor) HasInput(name string) bool {
	loc, err := e.locateAttr(e.rootSet(), []string{"inputs", name})
	return err == nil && len(loc.defs) != 0
}

// Undeclared named outputs arguments are implicit registry inputs in Nix.
// Overwriting one changes its source; leaving one behind after uninstall
// would silently recreate the removed input on the next lock operation.
func (e *FlakeEditor) implicitInput(name string) bool {
	_, outputs, _, _, err := e.lookupAttr(e.rootSet(), []string{"outputs"})
	if err != nil {
		return false
	}
	fn := importUnparen(outputs)
	if fn == nil || fn.Kind() != "function_expression" {
		return false
	}
	f := fn.ChildByFieldName("formals")
	for i := uint(0); f != nil && i < f.NamedChildCount(); i++ {
		if arg := f.NamedChild(i).
			ChildByFieldName("name"); arg != nil &&
			e.nodeText(arg) == name {
			return true
		}
	}
	return false
}

// AddInput reconciles a matching URL but never repoints an existing input.
func (e *FlakeEditor) AddInput(input FlakeInput) ([]byte, error) {
	return e.transaction(
		func(w *FlakeEditor) error { return w.reconcileInput(input, false) },
	)
}

// RemoveInput removes all (nested or dotted) declarations of exactly name.
func (e *FlakeEditor) RemoveInput(name string) ([]byte, error) {
	if err := e.editable(); err != nil {
		return nil, err
	}
	if !validIdent(name) || name == "self" {
		return nil, errors.New("invalid flake input name")
	}
	if e.implicitInput(name) {
		return nil, fmt.Errorf(
			"outputs has a named argument for input %q; remove that argument before uninstalling",
			name,
		)
	}
	return e.removeAttr(e.rootSet(), []string{"inputs", name})
}

func (e *FlakeEditor) removeAttr(set *tree_sitter.Node, path []string) ([]byte, error) {
	loc, err := e.locateAttr(set, path)
	if err != nil {
		return nil, err
	}
	nodes := make([]*tree_sitter.Node, 0, len(loc.defs))
	for _, def := range loc.defs {
		nodes = append(nodes, def.binding)
	}
	return e.removeNodes(nodes...), nil
}

// Scope ownership checks to the input itself. Nix accepts fetcher attributes
// besides url (e.g. follows, owner, host, dir); ignoring these could make a
// matching URL seem authoritative for an entirely different input.
func (e *FlakeEditor) checkInputShape(name string, loc attrLocation) error {
	check := func(key string, exact bool, value *tree_sitter.Node) error {
		switch key {
		case "inputs":
			return nil // nested overrides don't replace the input's own source
		case "url":
			if exact {
				return nil
			}
		case "flake":
			if exact && e.nodeText(value) == "true" {
				return nil
			}
		}
		return fmt.Errorf("input %q has unsupported source option %q", name, key)
	}
	for _, def := range loc.defs {
		if len(def.tail) != 0 {
			if err := check(def.tail[0], len(def.tail) == 1, def.value); err != nil {
				return err
			}
			continue
		}
		if len(loc.defs) != 1 || def.value.Kind() != "attrset_expression" {
			return fmt.Errorf("cannot reconcile non-literal input %q", name)
		}
		bs := e.findChildByKind(def.value, "binding_set")
		if bs == nil {
			continue
		}
		for i := uint(0); i < bs.NamedChildCount(); i++ {
			child := bs.NamedChild(i)
			if child.Kind() == "comment" {
				continue
			}
			key := child.ChildByFieldName("attrpath")
			if key == nil || key.NamedChildCount() == 0 {
				return fmt.Errorf("unsupported declaration in input %q", name)
			}
			k, ok := e.attrSegment(key.NamedChild(0))
			if !ok {
				return fmt.Errorf("computed source option on input %q", name)
			}
			if err := check(
				k,
				key.NamedChildCount() == 1,
				child.ChildByFieldName("expression"),
			); err != nil {
				return err
			}
		}
	}
	return nil
}

// resolveInput proves ownership from the live declaration, not a possibly
// stale flake.lock. Return the URL node, or its insertion site if absent.
func (e *FlakeEditor) resolveInput(
	input FlakeInput,
	want gitReference,
) (current gitReference, node, container *tree_sitter.Node, remaining []string, err error) {
	path := []string{"inputs", input.Name}
	loc, err := e.locateAttr(e.rootSet(), path)
	if err != nil {
		return current, nil, nil, nil, err
	}
	if err := e.checkInputShape(input.Name, loc); err != nil {
		return current, nil, nil, nil, err
	}
	_, node, container, remaining, err = e.lookupAttr(e.rootSet(), append(path, "url"))
	if err != nil {
		return current, nil, nil, nil, err
	}
	if node == nil && len(loc.defs) == 0 {
		if e.implicitInput(input.Name) {
			return current, nil, nil, nil, fmt.Errorf(
				"input %q already exists as an implicit outputs argument",
				input.Name,
			)
		}
		return current, nil, container, remaining, nil
	}
	raw, ok := e.plainString(node)
	if !ok {
		return current, nil, nil, nil, fmt.Errorf("input %q has no literal URL", input.Name)
	}
	current, err = parseReference(raw)
	if err != nil || current.base != want.base || current.options != want.options {
		return current, nil, nil, nil, fmt.Errorf(
			"input %q is already bound to a different source",
			input.Name,
		)
	}
	return current, node, container, remaining, nil
}

func (e *FlakeEditor) reconcileInput(input FlakeInput, update bool) error {
	if input.PreviousURL != "" {
		return errors.New("previous source only permitted on a registry update")
	}
	return e.reconcileInputFrom(input, update, "")
}

func (e *FlakeEditor) reconcileInputFrom(
	input FlakeInput,
	update bool,
	previousURL string,
) error {
	want, err := targetReference(input)
	if err != nil {
		return err
	}
	expected := want
	if previousURL != "" {
		expected, err = parseReference(previousURL)
		if err != nil {
			return err
		}
	}
	current, node, container, path, err := e.resolveInput(input, expected)
	if err != nil {
		return err
	}
	literal := `"` + want.URL() + `"` // targetReference rejects Nix escape/interpolation characters
	switch {
	case node == nil && update:
		return fmt.Errorf("input %q is not installed", input.Name)
	case node == nil:
		err = e.apply(
			e.appendAttr(container, strings.Join(path, ".")+" = "+literal+";"),
			nil,
		)
	case current != want && !update:
		return fmt.Errorf("input %q is already pinned to another version", input.Name)
	case current != want:
		err = e.apply(
			replaceRange(e.source, node.StartByte(), node.EndByte(), []byte(literal)),
			nil,
		)
	}
	if err != nil {
		return err
	}
	return e.reconcileFollow(input, update)
}

func (e *FlakeEditor) reconcileFollow(input FlakeInput, update bool) error {
	if !input.FollowsNixpkgs && !update {
		return nil // do not impose a follows on a matching user-supplied dependency
	}
	path := []string{"inputs", input.Name, "inputs", "nixpkgs", "follows"}
	b, v, container, rest, err := e.lookupAttr(e.rootSet(), path)
	if err != nil {
		return err
	}
	if b != nil {
		existing, literal := e.plainString(v)
		if !literal || existing != "nixpkgs" {
			if !input.FollowsNixpkgs {
				return nil // unrelated override; never remove it
			}
			return fmt.Errorf("input %q already has a different nixpkgs override", input.Name)
		}
		if !input.FollowsNixpkgs {
			// An empty `inputs.nixpkgs = {};` would become an indirect
			// input. Remove the whole override, but not unrelated fields.
			loc, err := e.locateAttr(e.rootSet(), path[:len(path)-1])
			if err != nil {
				return err
			}
			if len(loc.defs) != 1 {
				return fmt.Errorf("input %q has other nixpkgs overrides", input.Name)
			}
			def := loc.defs[0]
			if len(def.tail) == 0 {
				bs := e.findChildByKind(def.value, "binding_set")
				for j := uint(0); bs != nil && j < bs.NamedChildCount(); j++ {
					n := bs.NamedChild(j)
					if n.Kind() != "comment" && n.StartByte() != b.StartByte() {
						return fmt.Errorf("input %q has other nixpkgs overrides", input.Name)
					}
				}
			}
			return e.apply(e.removeNodes(def.binding), nil)
		}
		return nil
	}
	if input.FollowsNixpkgs {
		// A differently sourced nested nixpkgs input is not ours to replace.
		loc, err := e.locateAttr(e.rootSet(), path[:len(path)-1])
		if err != nil {
			return err
		}
		if len(loc.defs) != 0 {
			return fmt.Errorf("input %q already overrides nixpkgs", input.Name)
		}
		return e.apply(
			e.appendAttr(container, strings.Join(rest, ".")+` = "nixpkgs";`),
			nil,
		)
	}
	return nil
}

// AddInputAndImport is the explicit edit API used by `stack flake add-input`.
// An empty input-relative output path means add only the input.
func (e *FlakeEditor) AddInputAndImport(
	input FlakeInput,
	importPath string,
) (*EditResult, error) {
	r := &EditResult{InputAlreadyExists: e.HasInput(input.Name)}
	modified, err := e.transaction(func(w *FlakeEditor) error {
		if err := w.reconcileInput(input, false); err != nil {
			return err
		}
		r.InputAdded = !bytes.Equal(w.source, e.source)
		if importPath != "" {
			next, err := w.editModuleImport(input.Name, importPath, false, true)
			r.ImportAdded = !bytes.Equal(next, w.source)
			return w.apply(next, err)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	r.Modified = modified
	return r, nil
}

func (e *FlakeEditor) reconcileDeps(name string, deps []FlakeInput, update bool) error {
	for _, dep := range deps {
		if dep.Name == name {
			return fmt.Errorf("input %q cannot be its own dependency", name)
		}
		if err := e.reconcileDependency(name, dep, update); err != nil {
			return fmt.Errorf("dependency %q: %w", dep.Name, err)
		}
	}
	return nil
}

func (e *FlakeEditor) installModule(
	input FlakeInput,
	importPath string,
	deps []FlakeInput,
) ([]byte, error) {
	return e.transaction(func(w *FlakeEditor) error {
		if err := w.reconcileInput(input, false); err != nil {
			return err
		}
		if err := w.reconcileDeps(input.Name, deps, false); err != nil {
			return err
		}
		return w.apply(
			w.editModuleImport(input.Name, importPath, false, input.ExplicitImport),
		)
	})
}

func (e *FlakeEditor) uninstallRegistryModule(
	input FlakeInput,
	importPath string,
) ([]byte, error) {
	want, err := targetReference(input)
	if err != nil {
		return nil, err
	}
	return e.transaction(func(w *FlakeEditor) error {
		if _, _, _, _, err := w.resolveInput(input, want); err != nil {
			return err
		}
		if err := w.apply(w.editModuleImport(input.Name, importPath, true, false)); err != nil {
			return err
		}
		if err := w.apply(w.RemoveInput(input.Name)); err != nil {
			return err
		}
		return w.releaseDependencies(input.Name)
	})
}

func (e *FlakeEditor) updateModuleWithImports(
	input FlakeInput,
	previousPath, importPath string,
	deps []FlakeInput,
) ([]byte, error) {
	return e.transaction(func(w *FlakeEditor) error {
		if err := w.reconcileInputFrom(input, true, input.PreviousURL); err != nil {
			return err
		}
		if err := w.reconcileDeps(input.Name, deps, true); err != nil {
			return err
		}
		if err := w.releaseDependencies(input.Name, deps...); err != nil {
			return err
		}
		if previousPath != importPath {
			if err := w.apply(
				w.editModuleImport(input.Name, previousPath, true, false),
			); err != nil {
				return err
			}
		}
		return w.apply(
			w.editModuleImport(input.Name, importPath, false, input.ExplicitImport),
		)
	})
}
