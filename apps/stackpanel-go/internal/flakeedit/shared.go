// Package flakeedit provides tree-sitter based editing for Nix source files.
//
// Unlike JSON or YAML, Nix has no standard structured editing library. This
// package uses tree-sitter to parse Nix into a concrete syntax tree, then
// performs byte-offset surgery to insert/replace/delete while preserving the
// user's formatting, comments, and whitespace.
//
// Two editors are provided:
//   - NixEditor: general-purpose Nix attrset editing (for config.nix, data files)
//   - FlakeEditor: flake.nix-specific operations (inputs, imports)
package flakeedit

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	tree_sitter_nix "github.com/darkmatter/stackpanel/stackpanel-go/internal/treesitter/nix"
	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// configVariableExprPattern matches Nix expressions like:
//
//	config.variables."my-var-id".value
//
// These are references from app env bindings to global variables.
var configVariableExprPattern = regexp.MustCompile(`^\s*config\.variables\.("(?:[^"\\]|\\.)+").value\s*$`)
var nixStringLiteralPattern = regexp.MustCompile(`"(?:[^"\\]|\\.)*"`)

// importExprPattern matches a Nix `import <path> [args...]` expression where
// <path> is either an unquoted path literal (./foo, ../bar/baz.nix, /abs) or a
// quoted string. Captures the path token in group 1 and the quoted form in
// group 2 (if quoted) so callers can decide whether to unquote.
var importExprPattern = regexp.MustCompile(`^\s*import\s+(("(?:[^"\\]|\\.)*")|([^\s;]+))(?:\s|$|;)`)

// parseImportTarget extracts the path argument from an `import <path> ...`
// expression. Returns ("", false) for anything that isn't a top-level import
// call. Quoted paths are unquoted; bare path literals are returned as-is.
func parseImportTarget(expr string) (string, bool) {
	matches := importExprPattern.FindStringSubmatch(strings.TrimSpace(expr))
	if len(matches) == 0 {
		return "", false
	}
	if quoted := matches[2]; quoted != "" {
		unquoted, err := strconv.Unquote(quoted)
		if err != nil {
			return "", false
		}
		return unquoted, true
	}
	return matches[3], true
}

// parseConfigVariableExpr extracts the quoted variable ID from a
// config.variables."<id>".value expression, returning the unquoted ID.
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

func parseNixStringList(expr string) []string {
	matches := nixStringLiteralPattern.FindAllString(expr, -1)
	if len(matches) == 0 {
		return nil
	}

	values := make([]string, 0, len(matches))
	for _, match := range matches {
		value, err := strconv.Unquote(match)
		if err != nil {
			continue
		}
		values = append(values, value)
	}

	return values
}

// newParserAndTree creates a parser configured for Nix and parses source bytes.
func newParserAndTree(source []byte) (*tree_sitter.Parser, *tree_sitter.Tree, error) {
	parser := tree_sitter.NewParser()
	lang := tree_sitter.NewLanguage(tree_sitter_nix.Language())
	if err := parser.SetLanguage(lang); err != nil {
		parser.Close()
		return nil, nil, fmt.Errorf("failed to set Nix language: %w", err)
	}

	tree := parser.Parse(source, nil)
	if tree == nil {
		parser.Close()
		return nil, nil, errors.New("failed to parse source")
	}

	return parser, tree, nil
}

// insertAt inserts text at the given byte offset.
func insertAt(source []byte, offset uint, text []byte) []byte {
	result := make([]byte, 0, len(source)+len(text))
	result = append(result, source[:offset]...)
	result = append(result, text...)
	result = append(result, source[offset:]...)
	return result
}

// replaceRange replaces source bytes in [start,end).
func replaceRange(source []byte, start uint, end uint, text []byte) []byte {
	result := make([]byte, 0, len(source)-int(end-start)+len(text))
	result = append(result, source[:start]...)
	result = append(result, text...)
	result = append(result, source[end:]...)
	return result
}

// deleteRange removes source bytes in [start,end).
func deleteRange(source []byte, start uint, end uint) []byte {
	result := make([]byte, 0, len(source)-int(end-start))
	result = append(result, source[:start]...)
	result = append(result, source[end:]...)
	return result
}
