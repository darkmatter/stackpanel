package navigation

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

// createDeepCommandTree creates a test command tree with multiple levels
func createDeepCommandTree() *cobra.Command {
	root := &cobra.Command{
		Use:   "app",
		Short: "Test application",
	}

	// Level 1: services
	services := &cobra.Command{
		Use:   "services",
		Short: "Manage services",
	}

	// Level 2: services start, services stop
	servicesStart := &cobra.Command{
		Use:   "start",
		Short: "Start services",
	}
	servicesStop := &cobra.Command{
		Use:   "stop",
		Short: "Stop services",
	}

	// Level 2: services db (with nested commands)
	servicesDB := &cobra.Command{
		Use:   "db",
		Short: "Database operations",
	}

	// Level 3: services db migrate, services db seed
	dbMigrate := &cobra.Command{
		Use:   "migrate",
		Short: "Run migrations",
		Run:   func(cmd *cobra.Command, args []string) {},
	}
	dbSeed := &cobra.Command{
		Use:   "seed",
		Short: "Seed database",
		Run:   func(cmd *cobra.Command, args []string) {},
	}

	servicesDB.AddCommand(dbMigrate, dbSeed)
	services.AddCommand(servicesStart, servicesStop, servicesDB)

	// Level 1: config
	config := &cobra.Command{
		Use:   "config",
		Short: "Configuration commands",
	}

	// Level 2: config show, config edit
	configShow := &cobra.Command{
		Use:   "show",
		Short: "Show configuration",
		Run:   func(cmd *cobra.Command, args []string) {},
	}
	configEdit := &cobra.Command{
		Use:   "edit",
		Short: "Edit configuration",
		Run:   func(cmd *cobra.Command, args []string) {},
	}

	config.AddCommand(configShow, configEdit)

	root.AddCommand(services, config)
	return root
}

func TestDeepNavigationFlow(t *testing.T) {
	root := createDeepCommandTree()
	tree := BuildTree(root)

	// Navigate to services > db > migrate (3 levels deep, include root "app" in path)
	servicesNode := tree.FindByPath([]string{"app", "services"})
	if servicesNode == nil {
		t.Fatal("Could not find services node")
	}

	dbNode := tree.FindByPath([]string{"app", "services", "db"})
	if dbNode == nil {
		t.Fatal("Could not find services/db node")
	}

	migrateNode := tree.FindByPath([]string{"app", "services", "db", "migrate"})
	if migrateNode == nil {
		t.Fatal("Could not find services/db/migrate node")
	}

	// Verify path is correct (includes root "app")
	path := migrateNode.GetPath()
	if len(path) != 4 {
		t.Errorf("Expected path length 4, got %d", len(path))
	}
	if path[0] != "app" || path[1] != "services" || path[2] != "db" || path[3] != "migrate" {
		t.Errorf("Unexpected path: %v", path)
	}

	// Verify it's a leaf node
	if !migrateNode.IsLeaf {
		t.Error("migrate should be a leaf node")
	}
}

func TestBreadcrumbsAtAllLevels(t *testing.T) {
	root := createDeepCommandTree()
	tree := BuildTree(root)

	tests := []struct {
		path     []string
		expected string
	}{
		{
			path:     []string{"app"},
			expected: "app",
		},
		{
			path:     []string{"app", "services"},
			expected: "app > services",
		},
		{
			path:     []string{"app", "services", "db"},
			expected: "app > services > db",
		},
		{
			path:     []string{"app", "services", "db", "migrate"},
			expected: "app > services > db > migrate",
		},
		{
			path:     []string{"app", "config"},
			expected: "app > config",
		},
		{
			path:     []string{"app", "config", "show"},
			expected: "app > config > show",
		},
	}

	for _, tt := range tests {
		t.Run(strings.Join(tt.path, "/"), func(t *testing.T) {
			var node *CommandNode
			if len(tt.path) == 1 && tt.path[0] == "app" {
				node = tree.Root
			} else {
				node = tree.FindByPath(tt.path)
			}

			if node == nil {
				t.Fatalf("Could not find node at path: %v", tt.path)
			}

			breadcrumbs := RenderBreadcrumbs(node)
			// Check that all parts are present (ignoring styling)
			for _, part := range strings.Split(tt.expected, " > ") {
				if !strings.Contains(breadcrumbs, part) {
					t.Errorf("Breadcrumbs %q missing part %q", breadcrumbs, part)
				}
			}
		})
	}
}

func TestNavigationModelEscapeAtAllLevels(t *testing.T) {
	root := createDeepCommandTree()
	navModel := NewNavigationModel(root)

	// Set window size
	updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	navModel = updated.(NavigationModel)

	// Navigate down to services (include root "app" in path)
	navModel.currentNode = navModel.tree.FindByPath([]string{"app", "services"})
	if navModel.currentNode == nil {
		t.Fatal("Could not find services node")
	}
	navModel.menu = NewMenu(navModel.currentNode)
	navModel.selectionStack = append(navModel.selectionStack, 0) // Remember we were at index 0

	// Navigate down to db
	navModel.currentNode = navModel.tree.FindByPath([]string{"app", "services", "db"})
	if navModel.currentNode == nil {
		t.Fatal("Could not find services/db node")
	}
	navModel.menu = NewMenu(navModel.currentNode)
	navModel.selectionStack = append(navModel.selectionStack, 0)

	// Now we're at services/db, escape should go back to services
	newModel, _ := navModel.Update(tea.KeyMsg{Type: tea.KeyEscape})
	navModel = newModel.(NavigationModel)

	if navModel.currentNode.Name != "services" {
		t.Errorf("After first escape, expected to be at 'services', got '%s'", navModel.currentNode.Name)
	}

	// Escape again should go back to root
	newModel, _ = navModel.Update(tea.KeyMsg{Type: tea.KeyEscape})
	navModel = newModel.(NavigationModel)

	if navModel.currentNode.Name != "app" {
		t.Errorf("After second escape, expected to be at 'app', got '%s'", navModel.currentNode.Name)
	}
}

func TestMenuNavigationUpDown(t *testing.T) {
	root := createDeepCommandTree()
	tree := BuildTree(root)

	// Create menu at root level
	menu := NewMenu(tree.Root)

	// Should start at index 0
	if menu.SelectedIdx != 0 {
		t.Errorf("Menu should start at index 0, got %d", menu.SelectedIdx)
	}

	// Move down
	menu.MoveDown()
	if menu.SelectedIdx != 1 {
		t.Errorf("After MoveDown, expected index 1, got %d", menu.SelectedIdx)
	}

	// Move down again (should stay at 1 since there are only 2 items: config, services)
	menu.MoveDown()
	if menu.SelectedIdx != 1 {
		t.Errorf("Should not exceed max index, got %d", menu.SelectedIdx)
	}

	// Move up
	menu.MoveUp()
	if menu.SelectedIdx != 0 {
		t.Errorf("After MoveUp, expected index 0, got %d", menu.SelectedIdx)
	}

	// Move up again (should stay at 0)
	menu.MoveUp()
	if menu.SelectedIdx != 0 {
		t.Errorf("Should not go below 0, got %d", menu.SelectedIdx)
	}
}

func TestMenuSelectionRestoration(t *testing.T) {
	root := createDeepCommandTree()
	navModel := NewNavigationModel(root)

	// Set window size
	updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	navModel = updated.(NavigationModel)

	// Navigate to second item (index 1) at root level
	navModel.menu.MoveDown()
	savedIdx := navModel.menu.SelectedIdx

	// Navigate into that item (include root "app" in path)
	navModel.selectionStack = append(navModel.selectionStack, savedIdx)
	navModel.currentNode = navModel.tree.FindByPath([]string{"app", "services"})
	if navModel.currentNode == nil {
		t.Fatal("Could not find services node")
	}
	navModel.menu = NewMenu(navModel.currentNode)

	// Navigate back with escape
	newModel, _ := navModel.Update(tea.KeyMsg{Type: tea.KeyEscape})
	navModel = newModel.(NavigationModel)

	// Selection should be restored
	if navModel.menu.SelectedIdx != savedIdx {
		t.Errorf("Selection not restored: expected %d, got %d", savedIdx, navModel.menu.SelectedIdx)
	}
}

func TestLeafNodeDetection(t *testing.T) {
	root := createDeepCommandTree()
	tree := BuildTree(root)

	tests := []struct {
		path   []string
		isLeaf bool
	}{
		{[]string{"app", "services"}, false},
		{[]string{"app", "services", "db"}, false},
		{[]string{"app", "services", "db", "migrate"}, true},
		{[]string{"app", "services", "db", "seed"}, true},
		{[]string{"app", "config"}, false},
		{[]string{"app", "config", "show"}, true},
		{[]string{"app", "config", "edit"}, true},
	}

	for _, tt := range tests {
		t.Run(strings.Join(tt.path, "/"), func(t *testing.T) {
			node := tree.FindByPath(tt.path)
			if node == nil {
				t.Fatalf("Could not find node at path: %v", tt.path)
			}

			if node.IsLeaf != tt.isLeaf {
				t.Errorf("Node %s: expected IsLeaf=%v, got %v",
					strings.Join(tt.path, "/"), tt.isLeaf, node.IsLeaf)
			}
		})
	}
}

func TestQuitKeyAtAllLevels(t *testing.T) {
	root := createDeepCommandTree()

	levels := [][]string{
		{},                                     // root
		{"app", "services"},                    // level 1
		{"app", "services", "db"},              // level 2
		{"app", "services", "db", "migrate"},   // level 3 (leaf)
	}

	for _, path := range levels {
		t.Run(strings.Join(append([]string{"root"}, path...), "/"), func(t *testing.T) {
			navModel := NewNavigationModel(root)
			updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
			navModel = updated.(NavigationModel)

			// Navigate to the target level
			if len(path) > 0 {
				navModel.currentNode = navModel.tree.FindByPath(path)
				navModel.menu = NewMenu(navModel.currentNode)
			}

			// Press 'q'
			newModel, cmd := navModel.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})
			navModel = newModel.(NavigationModel)

			// Should be quitting
			if !navModel.quitting {
				t.Error("Should be quitting after pressing 'q'")
			}

			// Command should be tea.Quit
			if cmd == nil {
				t.Error("Expected quit command")
			}
		})
	}
}

func TestViewRendersWithoutPanic(t *testing.T) {
	root := createDeepCommandTree()
	navModel := NewNavigationModel(root)

	// Before window size - should not panic
	view := navModel.View()
	if view == "" {
		t.Error("View should return something even before window size")
	}

	// After window size
	updated, _ := navModel.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	navModel = updated.(NavigationModel)
	view = navModel.View()
	if view == "" {
		t.Error("View should return content after window size")
	}

	// At different levels
	for _, path := range [][]string{
		{"app", "services"},
		{"app", "services", "db"},
		{"app", "config"},
	} {
		navModel.currentNode = navModel.tree.FindByPath(path)
		navModel.menu = NewMenu(navModel.currentNode)
		view = navModel.View()
		if view == "" {
			t.Errorf("View should return content at path %v", path)
		}
	}
}
