package navigation

import (
	"testing"

	"github.com/spf13/cobra"
)

// createTestCommands creates a mock command hierarchy for testing
func createTestCommands() *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "stackpanel",
		Short: "Stackpanel development CLI",
	}

	// services command with subcommands
	servicesCmd := &cobra.Command{
		Use:   "services",
		Short: "Manage development services",
	}
	servicesCmd.AddCommand(&cobra.Command{
		Use:   "start",
		Short: "Start services",
		Run:   func(cmd *cobra.Command, args []string) {},
	})
	servicesCmd.AddCommand(&cobra.Command{
		Use:   "stop",
		Short: "Stop services",
		Run:   func(cmd *cobra.Command, args []string) {},
	})
	servicesCmd.AddCommand(&cobra.Command{
		Use:   "status",
		Short: "Show service status",
		Run:   func(cmd *cobra.Command, args []string) {},
	})

	// caddy command with subcommands
	caddyCmd := &cobra.Command{
		Use:   "caddy",
		Short: "Manage Caddy reverse proxy",
	}
	caddyCmd.AddCommand(&cobra.Command{
		Use:   "start",
		Short: "Start Caddy",
		Run:   func(cmd *cobra.Command, args []string) {},
	})
	caddyCmd.AddCommand(&cobra.Command{
		Use:   "stop",
		Short: "Stop Caddy",
		Run:   func(cmd *cobra.Command, args []string) {},
	})

	// status command (leaf)
	statusCmd := &cobra.Command{
		Use:   "status",
		Short: "Show development environment status",
		Run:   func(cmd *cobra.Command, args []string) {},
	}

	rootCmd.AddCommand(servicesCmd)
	rootCmd.AddCommand(caddyCmd)
	rootCmd.AddCommand(statusCmd)

	return rootCmd
}

func TestBuildTree(t *testing.T) {
	rootCmd := createTestCommands()
	tree := BuildTree(rootCmd)

	if tree == nil {
		t.Fatal("BuildTree returned nil")
	}
	if tree.Root == nil {
		t.Fatal("Tree has nil root")
	}
	if tree.Root.Name != "stackpanel" {
		t.Errorf("Root name = %q, want %q", tree.Root.Name, "stackpanel")
	}

	// Check children count (services, caddy, status - excluding help)
	if len(tree.Root.Children) != 3 {
		t.Errorf("Root has %d children, want 3", len(tree.Root.Children))
	}
}

func TestCommandNodeGetPath(t *testing.T) {
	rootCmd := createTestCommands()
	tree := BuildTree(rootCmd)

	// Find services > start using FindByPath (order-independent)
	startNode := tree.FindByPath([]string{"stackpanel", "services", "start"})
	if startNode == nil {
		t.Fatal("Could not find services > start node")
	}

	path := startNode.GetPath()
	expected := []string{"stackpanel", "services", "start"}

	if len(path) != len(expected) {
		t.Fatalf("Path length = %d, want %d", len(path), len(expected))
	}

	for i, name := range path {
		if name != expected[i] {
			t.Errorf("Path[%d] = %q, want %q", i, name, expected[i])
		}
	}
}

func TestCommandNodeIsLeaf(t *testing.T) {
	rootCmd := createTestCommands()
	tree := BuildTree(rootCmd)

	// Root should not be a leaf
	if tree.Root.IsLeaf {
		t.Error("Root should not be a leaf")
	}

	// services should not be a leaf (has children)
	servicesNode := tree.FindByPath([]string{"stackpanel", "services"})
	if servicesNode == nil {
		t.Fatal("Could not find services node")
	}
	if servicesNode.IsLeaf {
		t.Error("services should not be a leaf")
	}

	// services > start should be a leaf
	startNode := tree.FindByPath([]string{"stackpanel", "services", "start"})
	if startNode == nil {
		t.Fatal("Could not find services > start node")
	}
	if !startNode.IsLeaf {
		t.Error("services > start should be a leaf")
	}

	// status (root level) should be a leaf
	statusNode := tree.FindByPath([]string{"stackpanel", "status"})
	if statusNode == nil {
		t.Fatal("Could not find status node")
	}
	if !statusNode.IsLeaf {
		t.Error("status should be a leaf")
	}
}

func TestTreeFindByPath(t *testing.T) {
	rootCmd := createTestCommands()
	tree := BuildTree(rootCmd)

	tests := []struct {
		path     []string
		wantName string
		wantNil  bool
	}{
		{[]string{"stackpanel"}, "stackpanel", false},
		{[]string{"stackpanel", "services"}, "services", false},
		{[]string{"stackpanel", "services", "start"}, "start", false},
		{[]string{"stackpanel", "nonexistent"}, "", true},
		{[]string{"wrongroot"}, "", true},
		{[]string{}, "", true},
	}

	for _, tt := range tests {
		node := tree.FindByPath(tt.path)
		if tt.wantNil {
			if node != nil {
				t.Errorf("FindByPath(%v) = %v, want nil", tt.path, node.Name)
			}
		} else {
			if node == nil {
				t.Errorf("FindByPath(%v) = nil, want %q", tt.path, tt.wantName)
			} else if node.Name != tt.wantName {
				t.Errorf("FindByPath(%v).Name = %q, want %q", tt.path, node.Name, tt.wantName)
			}
		}
	}
}

func TestMenu(t *testing.T) {
	rootCmd := createTestCommands()
	tree := BuildTree(rootCmd)
	menu := NewMenu(tree.Root)

	if menu.IsEmpty() {
		t.Error("Menu should not be empty")
	}

	if len(menu.Items) != 3 {
		t.Errorf("Menu has %d items, want 3", len(menu.Items))
	}

	// Test navigation
	if menu.SelectedIdx != 0 {
		t.Errorf("Initial selection = %d, want 0", menu.SelectedIdx)
	}

	menu.MoveDown()
	if menu.SelectedIdx != 1 {
		t.Errorf("After MoveDown, selection = %d, want 1", menu.SelectedIdx)
	}

	menu.MoveUp()
	if menu.SelectedIdx != 0 {
		t.Errorf("After MoveUp, selection = %d, want 0", menu.SelectedIdx)
	}

	// Can't go above 0
	menu.MoveUp()
	if menu.SelectedIdx != 0 {
		t.Errorf("After extra MoveUp, selection = %d, want 0", menu.SelectedIdx)
	}

	menu.MoveToBottom()
	if menu.SelectedIdx != 2 {
		t.Errorf("After MoveToBottom, selection = %d, want 2", menu.SelectedIdx)
	}

	// Can't go below max
	menu.MoveDown()
	if menu.SelectedIdx != 2 {
		t.Errorf("After extra MoveDown, selection = %d, want 2", menu.SelectedIdx)
	}

	menu.MoveToTop()
	if menu.SelectedIdx != 0 {
		t.Errorf("After MoveToTop, selection = %d, want 0", menu.SelectedIdx)
	}
}

func TestMenuRender(t *testing.T) {
	rootCmd := createTestCommands()
	tree := BuildTree(rootCmd)
	menu := NewMenu(tree.Root)

	output := menu.Render()
	if output == "" {
		t.Error("Menu.Render() returned empty string")
	}

	// Should contain all item names
	for _, item := range menu.Items {
		if !containsString(output, item.Name) {
			t.Errorf("Rendered menu should contain %q", item.Name)
		}
	}
}

func TestBreadcrumbs(t *testing.T) {
	rootCmd := createTestCommands()
	tree := BuildTree(rootCmd)

	// Test breadcrumbs at root
	rootCrumbs := RenderBreadcrumbs(tree.Root)
	if rootCrumbs == "" {
		t.Error("Root breadcrumbs should not be empty")
	}
	if !containsString(rootCrumbs, "stackpanel") {
		t.Error("Root breadcrumbs should contain 'stackpanel'")
	}

	// Test breadcrumbs at nested level (use FindByPath for order-independence)
	startNode := tree.FindByPath([]string{"stackpanel", "services", "start"})
	if startNode == nil {
		t.Fatal("Could not find services > start node")
	}
	nestedCrumbs := RenderBreadcrumbs(startNode)
	if !containsString(nestedCrumbs, "stackpanel") {
		t.Error("Nested breadcrumbs should contain 'stackpanel'")
	}
	if !containsString(nestedCrumbs, "services") {
		t.Error("Nested breadcrumbs should contain 'services'")
	}
	if !containsString(nestedCrumbs, "start") {
		t.Error("Nested breadcrumbs should contain 'start'")
	}
}

func TestNavigationModel(t *testing.T) {
	rootCmd := createTestCommands()
	model := NewNavigationModel(rootCmd)

	// Should start at root
	if model.CurrentNode().Name != "stackpanel" {
		t.Errorf("Initial node = %q, want %q", model.CurrentNode().Name, "stackpanel")
	}

	// View should not be empty
	view := model.View()
	if view == "" {
		t.Error("Model.View() returned empty string")
	}
}

func containsString(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsStringHelper(s, substr))
}

func containsStringHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
