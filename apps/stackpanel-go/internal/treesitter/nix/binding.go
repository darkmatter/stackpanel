// Package nix provides tree-sitter grammar bindings for the Nix language.
//
// The C source files (parser.c, scanner.c) are vendored from:
// https://github.com/nix-community/tree-sitter-nix
//
// License: MIT
package nix

// #cgo CFLAGS: -std=c11 -fPIC
// #include "tree_sitter/parser.h"
// extern TSLanguage *tree_sitter_nix(void);
import "C"
import "unsafe"

// Language returns a pointer to the tree-sitter Nix language grammar.
// This is used with go-tree-sitter's NewLanguage() function.
func Language() unsafe.Pointer {
	return unsafe.Pointer(C.tree_sitter_nix())
}
