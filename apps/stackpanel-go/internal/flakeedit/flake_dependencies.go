package flakeedit

import (
	"bytes"
	"errors"
	"fmt"
	"slices"
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// Only a dependency newly created by the editor receives this comment inside
// its URL binding. Reusing a user's existing input never grants ownership.
// Removing the comment opts the binding out of automatic version migrations.
const depMarkerPrefix = "/* stackpanel:dependency "

func dependencyMarker(name, owner string) string {
	return depMarkerPrefix + name + " of " + owner + " */"
}

func (e *FlakeEditor) depMarker(
	name string,
) (url, marker *tree_sitter.Node, owner string, err error) {
	b, url, _, _, err := e.lookupAttr(e.rootSet(), []string{"inputs", name, "url"})
	if b == nil || err != nil {
		return url, nil, "", err
	}
	prefix := depMarkerPrefix + name + " of "
	for j := uint(0); j < b.NamedChildCount(); j++ {
		n := b.NamedChild(j)
		if n.Kind() != "comment" {
			continue
		}
		s := e.nodeText(n)
		if o := strings.TrimSuffix(
			strings.TrimPrefix(s, prefix),
			" */",
		); validIdent(o) &&
			s == dependencyMarker(name, o) {
			if marker != nil {
				return nil, nil, "", fmt.Errorf("ambiguous ownership of input %q", name)
			}
			marker, owner = n, o
		}
	}
	return url, marker, owner, nil
}

func (e *FlakeEditor) reconcileDependency(
	owner string,
	dep FlakeInput,
	update bool,
) error {
	prev := dep.PreviousDependency
	if !validIdent(owner) || dep.PreviousURL != "" ||
		prev != nil && (!update || prev.Name != dep.Name) {
		return errors.New("invalid catalog dependency transition")
	}
	want, err := targetReference(dep)
	if err != nil {
		return err
	}
	node, _, markedOwner, err := e.depMarker(dep.Name)
	if err != nil {
		return err
	}
	if prev != nil {
		if node == nil {
			return errors.New("previous catalog dependency has no live URL declaration")
		}
		old, err := targetReference(*prev)
		if err != nil {
			return err
		}
		if want != old || prev.FollowsNixpkgs != dep.FollowsNixpkgs {
			if markedOwner != owner {
				return errors.New("cannot change user-owned or shared dependency")
			}
			current, _, _, _, err := e.resolveInput(dep, old)
			if err != nil {
				return err
			}
			_, v, _, _, err := e.lookupAttr(
				e.rootSet(),
				[]string{"inputs", dep.Name, "inputs", "nixpkgs", "follows"},
			)
			if err != nil {
				return err
			}
			follows, static := e.plainString(v)
			if current != old || (v != nil) != prev.FollowsNixpkgs ||
				v != nil && (!static || follows != "nixpkgs") {
				return errors.New("dependency differs from the previous catalog release")
			}
			return e.reconcileInputFrom(dep, true, old.URL())
		}
	}
	if err := e.reconcileInput(dep, false); err != nil {
		return err
	}
	if node != nil && (markedOwner == "" || markedOwner == owner) {
		return nil
	}
	// Refresh AST offsets after the reconciliation (possibly added follows).
	u, mark, _, err := e.depMarker(dep.Name)
	if err != nil {
		return err
	}
	if node == nil {
		return e.apply(
			insertAt(e.source, u.EndByte(), []byte(" "+dependencyMarker(dep.Name, owner))),
			nil,
		)
	}
	// Another module now also needs this input. Relinquish exclusive control;
	// neither module may subsequently change the pin on the other's behalf.
	return e.apply(e.withoutMarker(mark), nil)
}

func (e *FlakeEditor) withoutMarker(n *tree_sitter.Node) []byte {
	start := n.StartByte()
	if start > 0 && e.source[start-1] == ' ' {
		start--
	}
	return replaceRange(e.source, start, n.EndByte(), []byte(""))
}

// Relinquish ownership on uninstall or when a release stops requiring a dep;
// the input itself stays in place. Only erase a marker in its own URL binding.
func (e *FlakeEditor) releaseDependencies(owner string, keep ...FlakeInput) error {
	if !bytes.Contains(e.source, []byte(depMarkerPrefix)) {
		return nil
	}
	var names []string
	var walk func(*tree_sitter.Node)
	walk = func(n *tree_sitter.Node) {
		if n.Kind() == "comment" {
			text := e.nodeText(n)
			name := strings.TrimSuffix(
				strings.TrimPrefix(text, depMarkerPrefix),
				" of "+owner+" */",
			)
			if validIdent(name) && text == dependencyMarker(name, owner) &&
				!slices.ContainsFunc(
					keep,
					func(dep FlakeInput) bool { return dep.Name == name },
				) {
				names = append(names, name)
			}
			return
		}
		for i := uint(0); i < n.NamedChildCount(); i++ {
			walk(n.NamedChild(i))
		}
	}
	walk(e.rootSet())
	for _, name := range names {
		_, marker, actual, err := e.depMarker(name)
		if err != nil {
			return err
		}
		if actual == owner {
			if err := e.apply(e.withoutMarker(marker), nil); err != nil {
				return err
			}
		}
	}
	return nil
}
