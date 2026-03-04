package cmd

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/fatih/color"
	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
)

var projectCmd = &cobra.Command{
	Use:   "project",
	Short: "Manage Stackpanel projects",
	Long: `Manage Stackpanel projects across your system.

Projects are stored in ~/.config/stackpanel/stackpanel.yaml and can be
accessed from any directory. Each project has a unique ID that can be
used in API requests via the X-Stackpanel-Project header.

Examples:
  stackpanel project list                  # List all known projects
  stackpanel project info                  # Show current project info
  stackpanel project default .             # Set current directory as default
  stackpanel project default --clear       # Clear default project`,
}

var projectListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all known projects",
	Long: `List all Stackpanel projects that have been registered.

Projects are automatically registered when you run 'stackpanel agent' from
a project directory, or when you use 'stackpanel project add'.`,
	Run: func(cmd *cobra.Command, args []string) {
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		projects := ucm.ListProjects()
		currentPath := ucm.CurrentProjectPath()
		defaultPath := ucm.GetDefaultProjectPath()

		if len(projects) == 0 {
			output.Info("No projects registered yet")
			fmt.Println()
			fmt.Printf("  Run %s from a project directory to register it.\n",
				color.CyanString("stackpanel agent"))
			return
		}

		fmt.Println(color.New(color.Bold).Sprint("Projects"))
		fmt.Println()

		for _, p := range projects {
			// Generate ID if not stored
			id := p.ID
			if id == "" {
				id = userconfig.GenerateProjectID(p.Path)
			}

			// Build status indicators
			var indicators []string
			if p.Path == currentPath {
				indicators = append(indicators, color.GreenString("current"))
			}
			if p.Path == defaultPath {
				indicators = append(indicators, color.YellowString("default"))
			}

			statusStr := ""
			if len(indicators) > 0 {
				statusStr = fmt.Sprintf(" (%s)", joinStrings(indicators, ", "))
			}

			// Format last opened time
			lastOpened := "never"
			if !p.LastOpened.IsZero() {
				lastOpened = formatRelativeTime(p.LastOpened)
			}

			fmt.Printf("  %s %s%s\n",
				color.CyanString(p.Name),
				color.New(color.Faint).Sprintf("[%s]", id),
				statusStr)
			fmt.Printf("    %s %s\n",
				color.New(color.Faint).Sprint("Path:"),
				p.Path)
			fmt.Printf("    %s %s\n",
				color.New(color.Faint).Sprint("Last opened:"),
				lastOpened)
			fmt.Println()
		}

		fmt.Println(color.New(color.Faint).Sprint("Use project ID or name in API requests:"))
		fmt.Printf("  %s\n", color.New(color.Faint).Sprint("curl -H 'X-Stackpanel-Project: <id>' http://localhost:9876/api/..."))
	},
}

var projectInfoCmd = &cobra.Command{
	Use:   "info [project]",
	Short: "Show information about a project",
	Long: `Show detailed information about a project.

Without arguments, shows information about the current project.
With an argument, shows information about the specified project (by ID, name, or path).`,
	Args: cobra.MaximumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		var proj *userconfig.Project
		identifier := ""

		if len(args) > 0 {
			identifier = args[0]
			proj = ucm.ResolveProject(identifier)
		} else {
			proj = ucm.CurrentProject()
		}

		if proj == nil {
			if identifier != "" {
				output.Error(fmt.Sprintf("Project not found: %s", identifier))
			} else {
				output.Error("No current project")
				fmt.Println()
				fmt.Printf("  Run %s to see available projects.\n",
					color.CyanString("stackpanel project list"))
			}
			os.Exit(1)
		}

		// Generate ID if not stored
		id := proj.ID
		if id == "" {
			id = userconfig.GenerateProjectID(proj.Path)
		}

		currentPath := ucm.CurrentProjectPath()
		defaultPath := ucm.GetDefaultProjectPath()

		fmt.Println(color.New(color.Bold).Sprint("Project Information"))
		fmt.Println()

		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Name:"), color.CyanString(proj.Name))
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("ID:"), id)
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Path:"), proj.Path)

		if !proj.LastOpened.IsZero() {
			fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Last opened:"),
				proj.LastOpened.Format(time.RFC3339))
		}

		fmt.Println()

		// Status flags
		if proj.Path == currentPath {
			fmt.Printf("  %s This is the current project\n", color.GreenString("●"))
		}
		if proj.Path == defaultPath {
			fmt.Printf("  %s This is the default project\n", color.YellowString("●"))
		}

		// Validation
		fmt.Println()
		if err := project.ValidateProject(proj.Path); err != nil {
			fmt.Printf("  %s Project validation failed: %s\n", color.RedString("✗"), err)
		} else {
			fmt.Printf("  %s Project is valid\n", color.GreenString("✓"))
		}

		// Usage hint
		fmt.Println()
		fmt.Println(color.New(color.Faint).Sprint("Use in API requests:"))
		fmt.Printf("  %s\n", color.New(color.Faint).Sprintf("curl -H 'X-Stackpanel-Project: %s' ...", id))
	},
}

var projectDefaultCmd = &cobra.Command{
	Use:   "default [path]",
	Short: "Set or show the default project",
	Long: `Set or show the default project.

The default project is used by the agent when no project is specified
in API requests (via X-Stackpanel-Project header or 'project' query param).

Without arguments, shows the current default project.
With a path argument, sets that project as the default.

Examples:
  stackpanel project default              # Show default project
  stackpanel project default .            # Set current directory as default
  stackpanel project default ~/myproject  # Set specific project as default
  stackpanel project default --clear      # Clear default project`,
	Args: cobra.MaximumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		clearDefault, _ := cmd.Flags().GetBool("clear")

		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		// Clear default
		if clearDefault {
			if err := ucm.ClearDefaultProject(); err != nil {
				output.Error(fmt.Sprintf("Failed to clear default: %v", err))
				os.Exit(1)
			}
			output.Success("Default project cleared")
			return
		}

		// No arguments - show current default
		if len(args) == 0 {
			proj := ucm.GetDefaultProject()
			if proj == nil {
				output.Info("No default project set")
				fmt.Println()
				fmt.Printf("  Set one with: %s\n",
					color.CyanString("stackpanel project default <path>"))
				return
			}

			id := proj.ID
			if id == "" {
				id = userconfig.GenerateProjectID(proj.Path)
			}

			fmt.Println(color.New(color.Bold).Sprint("Default Project"))
			fmt.Println()
			fmt.Printf("  %s %s %s\n",
				color.CyanString(proj.Name),
				color.New(color.Faint).Sprintf("[%s]", id),
				color.YellowString("(default)"))
			fmt.Printf("    %s %s\n",
				color.New(color.Faint).Sprint("Path:"),
				proj.Path)
			return
		}

		// Set default project
		projectPath := args[0]

		// Resolve the path
		if projectPath == "." {
			cwd, err := os.Getwd()
			if err != nil {
				output.Error(fmt.Sprintf("Failed to get current directory: %v", err))
				os.Exit(1)
			}
			projectPath = cwd
		}

		// Expand ~ if present
		if len(projectPath) > 0 && projectPath[0] == '~' {
			home, err := os.UserHomeDir()
			if err != nil {
				output.Error(fmt.Sprintf("Failed to get home directory: %v", err))
				os.Exit(1)
			}
			projectPath = filepath.Join(home, projectPath[1:])
		}

		// Make absolute
		absPath, err := filepath.Abs(projectPath)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to resolve path: %v", err))
			os.Exit(1)
		}

		// Check if project exists in list, if not, add it
		if !ucm.HasProject(absPath) {
			// Validate first
			if err := project.ValidateProject(absPath); err != nil {
				output.Error(fmt.Sprintf("Invalid project: %v", err))
				os.Exit(1)
			}

			// Add to projects list
			name := filepath.Base(absPath)
			if _, err := ucm.AddProject(absPath, name); err != nil {
				output.Error(fmt.Sprintf("Failed to add project: %v", err))
				os.Exit(1)
			}
			output.Info(fmt.Sprintf("Added project: %s", name))
		}

		// Set as default
		if err := ucm.SetDefaultProject(absPath); err != nil {
			output.Error(fmt.Sprintf("Failed to set default: %v", err))
			os.Exit(1)
		}

		// Get the project for display
		proj := ucm.GetProject(absPath)
		if proj == nil {
			output.Success("Default project set")
			return
		}

		id := userconfig.GenerateProjectID(absPath)

		output.Success("Default project set")
		fmt.Println()
		fmt.Printf("  %s %s\n", color.CyanString(proj.Name), color.New(color.Faint).Sprintf("[%s]", id))
		fmt.Printf("  %s\n", proj.Path)
		fmt.Println()
		output.Info("The agent will use this project when no project is specified in requests")
	},
}

var projectAddCmd = &cobra.Command{
	Use:   "add [path]",
	Short: "Add a project to the known projects list",
	Long: `Add a Stackpanel project to the known projects list.

Without arguments, adds the current directory.
With a path argument, adds that directory.

The project must be a valid Stackpanel project (has .stack/config.nix or flake.nix).

Examples:
  stackpanel project add              # Add current directory (with confirmation)
  stackpanel project add ~/myproject  # Add specific path (with confirmation)
  stackpanel project add -y           # Add without confirmation`,
	Args: cobra.MaximumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		skipConfirm, _ := cmd.Flags().GetBool("yes")
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		projectPath := "."
		if len(args) > 0 {
			projectPath = args[0]
		}

		// Resolve the path
		if projectPath == "." {
			cwd, err := os.Getwd()
			if err != nil {
				output.Error(fmt.Sprintf("Failed to get current directory: %v", err))
				os.Exit(1)
			}
			projectPath = cwd
		}

		// Expand ~ if present
		if len(projectPath) > 0 && projectPath[0] == '~' {
			home, err := os.UserHomeDir()
			if err != nil {
				output.Error(fmt.Sprintf("Failed to get home directory: %v", err))
				os.Exit(1)
			}
			projectPath = filepath.Join(home, projectPath[1:])
		}

		// Make absolute
		absPath, err := filepath.Abs(projectPath)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to resolve path: %v", err))
			os.Exit(1)
		}

		// Validate the project with detailed results
		validation := project.ValidateProjectDetailed(absPath, project.ValidationNormal)
		if validation.Error != nil {
			output.Error(fmt.Sprintf("Invalid project: %v", validation.Error))
			if len(validation.Warnings) > 0 {
				fmt.Println()
				output.Warning("Validation details:")
				for _, w := range validation.Warnings {
					fmt.Printf("  • %s\n", w)
				}
			}
			os.Exit(1)
		}

		// Show any warnings even for valid projects
		if len(validation.Warnings) > 0 {
			output.Warning("Validation warnings:")
			for _, w := range validation.Warnings {
				fmt.Printf("  • %s\n", w)
			}
			fmt.Println()
		}

		log.Debug().
			Str("type", validation.ProjectType).
			Strs("warnings", validation.Warnings).
			Msg("Project validation passed")

		// Check if already exists
		if ucm.HasProject(absPath) {
			output.Info("Project already registered")
			return
		}

		// Generate the project name and ID for display
		name := filepath.Base(absPath)
		id := userconfig.GenerateProjectID(absPath)

		// Show what will be added
		fmt.Println(color.New(color.Bold).Sprint("Project to add:"))
		fmt.Println()
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Name:"), color.CyanString(name))
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("ID:"), id)
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Path:"), absPath)
		fmt.Printf("  %s %s\n", color.New(color.Faint).Sprint("Type:"), validation.ProjectType)
		fmt.Println()

		// Prompt for confirmation unless -y flag
		if !skipConfirm {
			fmt.Print("Add this project? [y/N] ")
			reader := bufio.NewReader(os.Stdin)
			response, err := reader.ReadString('\n')
			if err != nil {
				output.Error("Failed to read input")
				os.Exit(1)
			}
			response = strings.TrimSpace(strings.ToLower(response))
			if response != "y" && response != "yes" {
				output.Info("Cancelled")
				return
			}
		}

		// Add the project
		proj, err := ucm.AddProject(absPath, name)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to add project: %v", err))
			os.Exit(1)
		}

		output.Success("Project added")
		fmt.Println()
		fmt.Printf("  %s %s\n", color.CyanString(proj.Name), color.New(color.Faint).Sprintf("[%s]", id))
		fmt.Printf("  %s\n", proj.Path)
	},
}

var projectRemoveCmd = &cobra.Command{
	Use:   "remove <project>",
	Short: "Remove a project from the known projects list",
	Long: `Remove a Stackpanel project from the known projects list.

The project can be specified by ID, name, or path.
This does not delete any files, only removes the project from the list.`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		ucm, err := userconfig.NewManager()
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load config: %v", err))
			os.Exit(1)
		}

		identifier := args[0]

		// Resolve the project
		proj := ucm.ResolveProject(identifier)
		if proj == nil {
			output.Error(fmt.Sprintf("Project not found: %s", identifier))
			os.Exit(1)
		}

		// Remove it
		if err := ucm.RemoveProject(proj.Path); err != nil {
			output.Error(fmt.Sprintf("Failed to remove project: %v", err))
			os.Exit(1)
		}

		output.Success(fmt.Sprintf("Removed project: %s", proj.Name))
	},
}

func init() {
	rootCmd.AddCommand(projectCmd)
	projectCmd.AddCommand(projectListCmd)
	projectCmd.AddCommand(projectInfoCmd)
	projectCmd.AddCommand(projectDefaultCmd)
	projectCmd.AddCommand(projectAddCmd)
	projectCmd.AddCommand(projectRemoveCmd)

	projectDefaultCmd.Flags().Bool("clear", false, "Clear the default project")
	projectAddCmd.Flags().BoolP("yes", "y", false, "Skip confirmation prompt")
}

// Helper functions

func joinStrings(strs []string, sep string) string {
	if len(strs) == 0 {
		return ""
	}
	result := strs[0]
	for i := 1; i < len(strs); i++ {
		result += sep + strs[i]
	}
	return result
}

func formatRelativeTime(t time.Time) string {
	now := time.Now()
	diff := now.Sub(t)

	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		mins := int(diff.Minutes())
		if mins == 1 {
			return "1 minute ago"
		}
		return fmt.Sprintf("%d minutes ago", mins)
	case diff < 24*time.Hour:
		hours := int(diff.Hours())
		if hours == 1 {
			return "1 hour ago"
		}
		return fmt.Sprintf("%d hours ago", hours)
	case diff < 7*24*time.Hour:
		days := int(diff.Hours() / 24)
		if days == 1 {
			return "yesterday"
		}
		return fmt.Sprintf("%d days ago", days)
	default:
		return t.Format("Jan 2, 2006")
	}
}
