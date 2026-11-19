package flakeedit

import (
	"bytes"
	"errors"
	"fmt"
	"slices"
	"strings"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

func (e *FlakeEditor) findChildByKind(
	node *tree_sitter.Node,
	kind string,
) *tree_sitter.Node {
	if node != nil {
		for i := uint(0); i < node.ChildCount(); i++ {
			if child := node.Child(i); child.Kind() == kind {
				return child
			}
		}
	}
	return nil
}

func (e *FlakeEditor) nodeText(node *tree_sitter.Node) string {
	return string(e.source[node.StartByte():node.EndByte()])
}

func (e *FlakeEditor) rootSet() *tree_sitter.Node {
	return e.findChildByKind(e.tree.RootNode(), "attrset_expression")
}

// plainString deliberately accepts only unescaped, non-interpolated Nix
// strings. Go's Unquote and Nix do not interpret escape sequences identically.
func (e *FlakeEditor) plainString(node *tree_sitter.Node) (string, bool) {
	if node == nil || node.Kind() != "string_expression" {
		return "", false
	}
	s := e.nodeText(node)
	if len(s) < 2 || strings.ContainsAny(s[1:len(s)-1], `\"`) ||
		strings.Contains(s, "${") {
		return "", false
	}
	return s[1 : len(s)-1], true
}

func (e *FlakeEditor) attrSegment(n *tree_sitter.Node) (string, bool) {
	if n.Kind() == "identifier" {
		return e.nodeText(n), true
	}
	if s, ok := e.plainString(n); ok {
		return s, true
	}
	if n.Kind() != "string_expression" {
		return "", false
	}
	// Decode Nix double-quoted attrnames, including literal \${...}. Never
	// evaluate an interpolation to decide which key to overwrite.
	s := e.nodeText(n)
	var b strings.Builder
	for i := 1; i < len(s)-1; i++ {
		ch := s[i]
		if ch == '$' && s[i+1] == '{' {
			return "", false
		}
		if ch == '\\' {
			i++
			ch = s[i]
			switch ch {
			case 'r':
				ch = '\r'
			case 'n':
				ch = '\n'
			case 't':
				ch = '\t'
			case '\\', '"', '$':
			default:
				return "", false
			}
		}
		b.WriteByte(ch)
	}
	return b.String(), true
}

type attrDefinition struct {
	binding, value *tree_sitter.Node
	tail           []string // suffix beyond the requested path (when dotted)
}

type attrLocation struct {
	defs      []attrDefinition
	container *tree_sitter.Node // innermost containing literal attrset
	remaining []string          // relative path for a missing leaf
}

// locateAttr follows only immediate bindings. A computed prefix, inherit, or
// non-literal ancestor that could cover the target is a conflict, not absence.
func (e *FlakeEditor) locateAttr(
	set *tree_sitter.Node,
	path []string,
) (attrLocation, error) {
	var loc attrLocation
	if set == nil || set.Kind() != "attrset_expression" || len(path) == 0 {
		return loc, errors.New("expected literal Nix attribute set")
	}
	loc.container, loc.remaining = set, path
	bs := e.findChildByKind(set, "binding_set")
	if bs == nil {
		return loc, nil
	}
	var ancestor *tree_sitter.Node
	var suffix []string
	for i := uint(0); i < bs.NamedChildCount(); i++ {
		b := bs.NamedChild(i)
		switch b.Kind() {
		case "comment":
			continue
		case "inherit", "inherit_from":
			attrs := b.ChildByFieldName("attrs")
			if attrs == nil {
				return loc, errors.New("unsupported inherited attribute")
			}
			for j := uint(0); j < attrs.NamedChildCount(); j++ {
				n := attrs.NamedChild(j)
				if n.Kind() == "comment" {
					continue
				}
				if name, ok := e.attrSegment(n); !ok || name == path[0] {
					return loc, fmt.Errorf("cannot edit inherited attribute %q", path[0])
				}
			}
			continue
		case "binding":
		default:
			return loc, fmt.Errorf("unsupported declaration %s", b.Kind())
		}
		key := b.ChildByFieldName("attrpath")
		value := b.ChildByFieldName("expression")
		if key == nil || value == nil {
			return loc, errors.New("malformed attribute binding")
		}
		matched, unrelated := 0, false
		var tail []string
		for j := uint(0); j < key.NamedChildCount(); j++ {
			n := key.NamedChild(j)
			if n.Kind() == "comment" {
				continue
			}
			name, known := e.attrSegment(n)
			if !known {
				return loc, fmt.Errorf("computed key overlaps %s", strings.Join(path, "."))
			}
			if matched < len(path) && name != path[matched] {
				unrelated = true
				break
			}
			if matched >= len(path) {
				tail = append(tail, name)
			}
			matched++
		}
		if unrelated {
			continue
		}
		if matched < len(path) {
			if ancestor != nil || value.Kind() != "attrset_expression" {
				return loc, fmt.Errorf(
					"ambiguous or computed parent of %s",
					strings.Join(path, "."),
				)
			}
			ancestor, suffix = value, path[matched:]
		} else {
			loc.defs = append(loc.defs, attrDefinition{b, value, tail})
		}
	}
	if ancestor != nil {
		if len(loc.defs) != 0 {
			return loc, fmt.Errorf("mixed declarations of %s", strings.Join(path, "."))
		}
		return e.locateAttr(ancestor, suffix)
	}
	return loc, nil
}

func (e *FlakeEditor) lookupAttr(
	set *tree_sitter.Node,
	path []string,
) (binding, value, container *tree_sitter.Node, remaining []string, err error) {
	loc, err := e.locateAttr(set, path)
	if err != nil {
		return nil, nil, nil, nil, err
	}
	if len(loc.defs) == 0 {
		return nil, nil, loc.container, loc.remaining, nil
	}
	if len(loc.defs) != 1 || len(loc.defs[0].tail) > 0 {
		return nil, nil, nil, nil, fmt.Errorf(
			"expected one binding at %s",
			strings.Join(path, "."),
		)
	}
	return loc.defs[0].binding, loc.defs[0].value, loc.container, nil, nil
}

func (e *FlakeEditor) lineStart(pos uint) uint {
	return uint(bytes.LastIndexByte(e.source[:pos], '\n') + 1)
}

func (e *FlakeEditor) appendAttr(set *tree_sitter.Node, declaration string) []byte {
	end := set.EndByte() - 1 // caller has a parse-checked literal attrset
	start := e.lineStart(end)
	closingIndent := string(e.source[start:end])
	if strings.Trim(closingIndent, " \t") != "" {
		return insertAt(e.source, end, []byte(" "+declaration+" "))
	}
	indent := closingIndent + "  "
	if b := e.findChildByKind(set, "binding_set"); b != nil {
		prefix := string(e.source[e.lineStart(b.StartByte()):b.StartByte()])
		if strings.Trim(prefix, " \t") == "" {
			indent = prefix
		}
	}
	return insertAt(e.source, start, []byte(indent+declaration+"\n"))
}

// Remove non-overlapping declarations/list items. Preserve comments *inside*
// deleted nodes too, including the newline terminating a Nix line comment.
func (e *FlakeEditor) removeNodes(nodes ...*tree_sitter.Node) []byte {
	slices.SortFunc(
		nodes,
		func(a, b *tree_sitter.Node) int { return int(b.StartByte()) - int(a.StartByte()) },
	)
	source := e.source
	for _, n := range nodes {
		var keep strings.Builder
		var comments func(*tree_sitter.Node)
		comments = func(x *tree_sitter.Node) {
			if x.Kind() == "comment" {
				keep.WriteString(e.nodeText(x))
				keep.WriteByte('\n')
				return
			}
			for i := uint(0); i < x.NamedChildCount(); i++ {
				comments(x.NamedChild(i))
			}
		}
		comments(n)
		start, end := n.StartByte(), n.EndByte()
		if keep.Len() == 0 {
			line := e.lineStart(start)
			nl := bytes.IndexByte(source[end:], '\n')
			if nl >= 0 && len(bytes.TrimSpace(source[line:start])) == 0 &&
				len(bytes.TrimSpace(source[end:end+uint(nl)])) == 0 {
				start, end = line, end+uint(nl)+1
			} else if start > 0 && end < uint(len(source)) && len(bytes.TrimSpace(source[start-1:start])) != 0 &&
				len(bytes.TrimSpace(source[end:end+1])) != 0 {
				// Never fuse the neighbors of a removed parenthesized list item.
				keep.WriteByte(' ')
			}
		}
		source = replaceRange(source, start, end, []byte(keep.String()))
	}
	return source
}
