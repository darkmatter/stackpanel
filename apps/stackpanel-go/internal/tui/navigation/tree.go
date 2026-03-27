package navigation

import (
	"github.com/spf13/cobra"
)

// CommandNode represents a node in the command tree. Each node maps 1:1 to a
// Cobra command. Leaf nodes are executable; non-leaf nodes are navigable
// containers. Parent pointers enable breadcrumb rendering and back-navigation.
type CommandNode struct {
	Name        string
	Description string
	IsLeaf      bool // True when the command has no visible subcommands
	Children    []*CommandNode
	Parent      *CommandNode
	CobraCmd    *cobra.Command // Reference back to the underlying Cobra command
}

// CommandTree holds the root of the command tree
type CommandTree struct {
	Root *CommandNode
}

// BuildTree converts a Cobra command hierarchy into a CommandTree for TUI navigation.
// Hidden commands, "help", and "completion" are filtered out.
func BuildTree(rootCmd *cobra.Command) *CommandTree {
	root := buildNode(rootCmd, nil)
	return &CommandTree{Root: root}
}

// buildNode recursively builds CommandNode tree from cobra commands
func buildNode(cmd *cobra.Command, parent *CommandNode) *CommandNode {
	subcommands := getVisibleSubcommands(cmd)

	node := &CommandNode{
		Name:        cmd.Name(),
		Description: cmd.Short,
		IsLeaf:      len(subcommands) == 0,
		Parent:      parent,
		CobraCmd:    cmd,
	}

	for _, sub := range subcommands {
		child := buildNode(sub, node)
		node.Children = append(node.Children, child)
	}

	return node
}

// getVisibleSubcommands filters out hidden, help, and completion commands
// that shouldn't appear in the interactive menu.
func getVisibleSubcommands(cmd *cobra.Command) []*cobra.Command {
	var visible []*cobra.Command
	for _, sub := range cmd.Commands() {
		// Skip hidden commands and help command
		if sub.Hidden || sub.Name() == "help" || sub.Name() == "completion" {
			continue
		}
		visible = append(visible, sub)
	}
	return visible
}

// GetPath returns the path from root to this node as a slice of names.
// The returned slice always starts with the root command name.
// Used for breadcrumb rendering and reconstructing Cobra args.
func (n *CommandNode) GetPath() []string {
	var path []string
	current := n
	for current != nil {
		path = append([]string{current.Name}, path...)
		current = current.Parent
	}
	return path
}

// GetPathNodes returns the path from root to this node as a slice of nodes
func (n *CommandNode) GetPathNodes() []*CommandNode {
	var path []*CommandNode
	current := n
	for current != nil {
		path = append([]*CommandNode{current}, path...)
		current = current.Parent
	}
	return path
}

// FindByPath finds a node by following a path of command names from the root
func (t *CommandTree) FindByPath(path []string) *CommandNode {
	if len(path) == 0 || path[0] != t.Root.Name {
		return nil
	}

	current := t.Root
	for _, name := range path[1:] {
		found := false
		for _, child := range current.Children {
			if child.Name == name {
				current = child
				found = true
				break
			}
		}
		if !found {
			return nil
		}
	}
	return current
}

// CanExecute returns true if this node represents an executable command
// A command is executable if it has a Run or RunE function and is a leaf
func (n *CommandNode) CanExecute() bool {
	if n.CobraCmd == nil {
		return false
	}
	// A command is executable if it has a Run function
	// and either has no children OR has its own run behavior
	return n.CobraCmd.Run != nil || n.CobraCmd.RunE != nil
}

// HasRequiredArgs returns true if the command requires arguments.
// Uses a heuristic: looks for <angle-bracket> patterns in the Use string.
// This avoids reflection on Cobra's Args field, which uses function values
// that can't be introspected (ExactArgs, MinimumNArgs, etc.).
func (n *CommandNode) HasRequiredArgs() bool {
	if n.CobraCmd == nil {
		return false
	}
	return containsRequiredArg(n.CobraCmd.Use)
}

// containsRequiredArg checks if a use string contains required argument markers
func containsRequiredArg(use string) bool {
	// Required args are usually marked with <arg>
	// Optional args are usually marked with [arg]
	inRequired := false
	for _, ch := range use {
		if ch == '<' {
			inRequired = true
		} else if ch == '>' {
			if inRequired {
				return true
			}
		}
	}
	return false
}
