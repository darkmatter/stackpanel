package navigation

import (
	"github.com/spf13/cobra"
)

// CommandNode represents a node in the command tree
type CommandNode struct {
	Name        string
	Description string
	IsLeaf      bool
	Children    []*CommandNode
	Parent      *CommandNode
	CobraCmd    *cobra.Command
}

// CommandTree holds the root of the command tree
type CommandTree struct {
	Root *CommandNode
}

// BuildTree builds a command tree from a cobra command hierarchy
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

// getVisibleSubcommands returns commands that should be visible in the menu
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

// GetPath returns the path from root to this node as a slice of names
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

// HasRequiredArgs returns true if the command requires arguments
func (n *CommandNode) HasRequiredArgs() bool {
	if n.CobraCmd == nil {
		return false
	}
	// Check if Args is set and requires arguments
	// This is a heuristic - cobra.ExactArgs(n) with n > 0 means required
	// For simplicity, we check the Use string for <arg> patterns
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
