package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

// SerializableCommand represents a command from the Nix config
type SerializableCommand struct {
	Name        string            `json:"name"`
	Exec        string            `json:"exec"`
	Description *string           `json:"description"`
	Env         map[string]string `json:"env"`
}

// StackpanelConfig represents the relevant parts of the serialized config
type StackpanelConfig struct {
	// New location: scripts are at the root level
	Scripts map[string]SerializableCommand `json:"scripts"`
	Devshell struct {
		// Legacy: _commandsSerializable (kept for backwards compatibility)
		CommandsSerializable map[string]SerializableCommand `json:"_commandsSerializable"`
		Env                  map[string]string              `json:"env"`
	} `json:"devshell"`
}

var commandsCmd = &cobra.Command{
	Use:     "commands [command-name] [args...]",
	Aliases: []string{"cmd", "run"},
	Short:   "List or run devshell commands",
	Long: `List or run commands defined in the Nix devshell configuration.

Without arguments, lists all available commands.
With a command name, runs that command with any additional arguments.

Examples:
  stackpanel commands                    # List all commands
  stackpanel commands secrets:list       # Run the secrets:list command
  stackpanel run generate-types          # Run generate-types (using alias)
  stackpanel cmd build --release         # Run build with --release flag`,
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()

		// Get config from nix eval
		config, err := getStackpanelConfig(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to get config: %v", err))
			os.Exit(1)
		}

		// Use scripts (new location) with fallback to legacy _commandsSerializable
		commands := config.Scripts
		if len(commands) == 0 {
			commands = config.Devshell.CommandsSerializable
		}

		if len(args) == 0 {
			// List commands
			listCommands(commands)
			return
		}

		// Run the specified command
		cmdName := args[0]
		cmdArgs := args[1:]

		cmdDef, ok := commands[cmdName]
		if !ok {
			output.Error(fmt.Sprintf("Unknown command: %s", cmdName))
			fmt.Println()
			fmt.Println("Available commands:")
			listCommands(commands)
			os.Exit(1)
		}

		if err := runCommand(cmdDef, cmdArgs, config.Devshell.Env); err != nil {
			output.Error(fmt.Sprintf("Command failed: %v", err))
			os.Exit(1)
		}
	},
}

var commandsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all available commands",
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()

		config, err := getStackpanelConfig(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to get config: %v", err))
			os.Exit(1)
		}

		// Use scripts (new location) with fallback to legacy _commandsSerializable
		commands := config.Scripts
		if len(commands) == 0 {
			commands = config.Devshell.CommandsSerializable
		}
		listCommands(commands)
	},
}

func init() {
	rootCmd.AddCommand(commandsCmd)
	commandsCmd.AddCommand(commandsListCmd)
}

func getStackpanelConfig(ctx context.Context) (*StackpanelConfig, error) {
	// Use nixeval to get the serialized config from the flake output
	// This uses .#stackpanelConfig which includes computed values like _commandsSerializable
	result, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		Expression: nixeval.StackpanelSerializablePreset,
	})
	if err != nil {
		return nil, fmt.Errorf("nix eval failed: %w", err)
	}

	var config StackpanelConfig
	if err := json.Unmarshal(result, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	return &config, nil
}

func listCommands(commands map[string]SerializableCommand) {
	if len(commands) == 0 {
		output.Warning("No commands defined in devshell")
		return
	}

	// Sort commands by name
	names := make([]string, 0, len(commands))
	for name := range commands {
		names = append(names, name)
	}
	sort.Strings(names)

	// Group commands by prefix (before ':')
	groups := make(map[string][]string)
	ungrouped := []string{}

	for _, name := range names {
		if idx := strings.Index(name, ":"); idx > 0 {
			prefix := name[:idx]
			groups[prefix] = append(groups[prefix], name)
		} else {
			ungrouped = append(ungrouped, name)
		}
	}

	// Print ungrouped commands first
	if len(ungrouped) > 0 {
		fmt.Println(color.New(color.Bold).Sprint("Commands:"))
		for _, name := range ungrouped {
			printCommandEntry(name, commands[name])
		}
		fmt.Println()
	}

	// Print grouped commands
	groupNames := make([]string, 0, len(groups))
	for g := range groups {
		groupNames = append(groupNames, g)
	}
	sort.Strings(groupNames)

	for _, groupName := range groupNames {
		fmt.Println(color.New(color.Bold).Sprintf("%s:", groupName))
		for _, name := range groups[groupName] {
			printCommandEntry(name, commands[name])
		}
		fmt.Println()
	}
}

func printCommandEntry(name string, cmd SerializableCommand) {
	nameColor := color.New(color.FgCyan)
	descColor := color.New(color.Faint)

	if cmd.Description != nil && *cmd.Description != "" {
		fmt.Printf("  %s  %s\n", nameColor.Sprint(name), descColor.Sprint(*cmd.Description))
	} else {
		fmt.Printf("  %s\n", nameColor.Sprint(name))
	}
}

func runCommand(cmdDef SerializableCommand, args []string, devshellEnv map[string]string) error {
	// Build the script to execute
	// The exec field contains the bash script to run
	script := cmdDef.Exec

	// If there are args, append them to the script
	if len(args) > 0 {
		// Quote args properly
		quotedArgs := make([]string, len(args))
		for i, arg := range args {
			quotedArgs[i] = shellescape(arg)
		}
		script = script + " " + strings.Join(quotedArgs, " ")
	}

	// Wrap in bash with error handling
	fullScript := fmt.Sprintf("set -euo pipefail\n%s", script)

	// Debug: print the script being executed
	if os.Getenv("STACKPANEL_DEBUG") != "" {
		fmt.Fprintf(os.Stderr, "[DEBUG] Executing script:\n%s\n", fullScript)
	}

	// Create the command
	cmd := exec.Command("bash", "-c", fullScript)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	// Set up environment
	cmd.Env = os.Environ()

	// Add devshell env vars
	for k, v := range devshellEnv {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	// Add command-specific env vars
	for k, v := range cmdDef.Env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	return cmd.Run()
}

// shellescape escapes a string for safe use in a shell command
func shellescape(s string) string {
	// If the string is simple (alphanumeric, dash, underscore, dot, slash), return as-is
	safe := true
	for _, r := range s {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') ||
			r == '-' || r == '_' || r == '.' || r == '/' || r == ':' || r == '=') {
			safe = false
			break
		}
	}
	if safe && s != "" {
		return s
	}

	// Otherwise, wrap in single quotes and escape any single quotes
	return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'"
}
