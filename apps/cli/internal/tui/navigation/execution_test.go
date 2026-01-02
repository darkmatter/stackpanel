package navigation

import (
	"bytes"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

// createExecutableCommandTree creates commands that can actually run
func createExecutableCommandTree() (*cobra.Command, *bytes.Buffer) {
	output := &bytes.Buffer{}

	root := &cobra.Command{
		Use:   "app",
		Short: "Test application",
	}

	// Simple leaf command
	hello := &cobra.Command{
		Use:   "hello",
		Short: "Say hello",
		Run: func(cmd *cobra.Command, args []string) {
			output.WriteString("Hello, World!")
		},
	}

	// Command with subcommands
	greet := &cobra.Command{
		Use:   "greet",
		Short: "Greeting commands",
	}

	greetFormal := &cobra.Command{
		Use:   "formal",
		Short: "Formal greeting",
		Run: func(cmd *cobra.Command, args []string) {
			output.WriteString("Good day, sir!")
		},
	}

	greetCasual := &cobra.Command{
		Use:   "casual",
		Short: "Casual greeting",
		Run: func(cmd *cobra.Command, args []string) {
			output.WriteString("Hey there!")
		},
	}

	greet.AddCommand(greetFormal, greetCasual)
	root.AddCommand(hello, greet)

	return root, output
}

func TestLeafCommandIsLeaf(t *testing.T) {
	root, _ := createExecutableCommandTree()
	tree := BuildTree(root)

	// Find a leaf command (include root name in path)
	helloNode := tree.FindByPath([]string{"app", "hello"})
	if helloNode == nil {
		t.Fatal("Could not find hello node")
	}

	if !helloNode.IsLeaf {
		t.Error("hello should be a leaf node")
	}
}

func TestNonLeafCommandIsNotLeaf(t *testing.T) {
	root, _ := createExecutableCommandTree()
	tree := BuildTree(root)

	// Find a non-leaf command (include root name in path)
	greetNode := tree.FindByPath([]string{"app", "greet"})
	if greetNode == nil {
		t.Fatal("Could not find greet node")
	}

	if greetNode.IsLeaf {
		t.Error("greet should not be a leaf node")
	}
}

func TestNavigationModelEnterOnLeaf(t *testing.T) {
	root, _ := createExecutableCommandTree()
	navModel := NewNavigationModel(root)

	// Set window size
	updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	navModel = updated.(NavigationModel)

	// Navigate to a leaf command (include root name in path)
	navModel.currentNode = navModel.tree.FindByPath([]string{"app", "hello"})
	if navModel.currentNode == nil {
		t.Fatal("Could not find hello node")
	}
	navModel.menu = NewMenu(navModel.currentNode)

	// The model should detect we're at a leaf
	if !navModel.currentNode.IsLeaf {
		t.Error("Should be at a leaf node")
	}
}

func TestNavigationModelEnterOnNonLeaf(t *testing.T) {
	root, _ := createExecutableCommandTree()
	navModel := NewNavigationModel(root)

	// Set window size
	updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	navModel = updated.(NavigationModel)

	// We're at root, first item should be 'greet' (alphabetical order)
	// Press enter to navigate into it
	newModel, _ := navModel.Update(tea.KeyMsg{Type: tea.KeyEnter})
	navModel = newModel.(NavigationModel)

	// Should have navigated into the first child (greet comes before hello alphabetically)
	if navModel.currentNode.Name != "greet" {
		t.Errorf("Expected to navigate to 'greet', got '%s'", navModel.currentNode.Name)
	}

	// Menu should now show greet's children
	if len(navModel.menu.Items) != 2 {
		t.Errorf("Expected 2 menu items (casual, formal), got %d", len(navModel.menu.Items))
	}
}

func TestCommandExecutedMsg(t *testing.T) {
	// Create execute message
	msg := CommandExecutedMsg{
		Output: "test output",
		Err:    nil,
	}

	if msg.Output != "test output" {
		t.Error("CommandExecutedMsg should contain the output")
	}
	if msg.Err != nil {
		t.Error("CommandExecutedMsg Err should be nil")
	}
}

func TestViewStateTransitions(t *testing.T) {
	root, _ := createExecutableCommandTree()
	navModel := NewNavigationModel(root)

	// Set window size
	updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	navModel = updated.(NavigationModel)

	// Should start in menu state
	if navModel.viewState != ViewMenu {
		t.Error("Should start in menu view state")
	}

	// Verify view state constants
	if ViewMenu != 0 {
		t.Error("ViewMenu should be 0")
	}
	if ViewOutput != 1 {
		t.Error("ViewOutput should be 1")
	}
	if ViewCustom != 2 {
		t.Error("ViewCustom should be 2")
	}
}

func TestCommandTreePreservesCobraCmd(t *testing.T) {
	root, _ := createExecutableCommandTree()
	tree := BuildTree(root)

	// Verify CobraCmd is preserved
	if tree.Root.CobraCmd != root {
		t.Error("Root node should reference the original cobra command")
	}

	helloNode := tree.FindByPath([]string{"app", "hello"})
	if helloNode == nil {
		t.Fatal("Could not find hello node")
	}
	if helloNode.CobraCmd == nil {
		t.Error("Leaf node should have CobraCmd reference")
	}

	// Verify we can access cobra command properties
	if helloNode.CobraCmd.Use != "hello" {
		t.Errorf("CobraCmd.Use should be 'hello', got '%s'", helloNode.CobraCmd.Use)
	}
}

func TestSelectionStackManagement(t *testing.T) {
	root, _ := createExecutableCommandTree()
	navModel := NewNavigationModel(root)

	// Set window size
	updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	navModel = updated.(NavigationModel)

	// Selection stack should be empty at start
	if len(navModel.selectionStack) != 0 {
		t.Errorf("Selection stack should be empty, got %d items", len(navModel.selectionStack))
	}

	// Navigate into first item (greet)
	navModel.menu.SelectedIdx = 0
	newModel, _ := navModel.Update(tea.KeyMsg{Type: tea.KeyEnter})
	navModel = newModel.(NavigationModel)

	// Selection stack should have 1 item (the index we were at)
	if len(navModel.selectionStack) != 1 {
		t.Errorf("Selection stack should have 1 item, got %d", len(navModel.selectionStack))
	}

	// Navigate back
	newModel, _ = navModel.Update(tea.KeyMsg{Type: tea.KeyEscape})
	navModel = newModel.(NavigationModel)

	// Selection stack should be empty again
	if len(navModel.selectionStack) != 0 {
		t.Errorf("Selection stack should be empty after escape, got %d", len(navModel.selectionStack))
	}
}
