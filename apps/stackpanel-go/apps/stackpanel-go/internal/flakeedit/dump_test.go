package flakeedit

import (
	"fmt"
	"os"
	"strings"
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_nix "github.com/darkmatter/stackpanel/stackpanel-go/internal/treesitter/nix"
)

func printTree(node *tree_sitter.Node, source []byte, indent int) {
	prefix := strings.Repeat("  ", indent)
	text := ""
	if node.ChildCount() == 0 {
		t := string(source[node.StartByte():node.EndByte()])
		if len(t) > 60 {
			t = t[:60] + "..."
		}
		text = fmt.Sprintf(" %q", t)
	}
	fmt.Printf("%s(%s [%d:%d-%d:%d]%s)\n", prefix, node.Kind(),
		node.StartPosition().Row, node.StartPosition().Column,
		node.EndPosition().Row, node.EndPosition().Column,
		text)
	for i := uint(0); i < uint(node.ChildCount()); i++ {
		child := node.Child(i)
		printTree(child, source, indent+1)
	}
}

func TestDumpAST(t *testing.T) {
	source, err := os.ReadFile("../../flake.nix")
	if err != nil {
		source, err = os.ReadFile("../../../../flake.nix")
		if err != nil {
			t.Skip("flake.nix not found")
		}
	}
	parser := tree_sitter.NewParser()
	defer parser.Close()
	parser.SetLanguage(tree_sitter.NewLanguage(tree_sitter_nix.Language()))
	tree := parser.Parse(source, nil)
	defer tree.Close()
	printTree(tree.RootNode(), source, 0)
}
