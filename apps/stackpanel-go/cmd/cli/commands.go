// commands.go lists and runs user-defined devshell commands (scripts).
//
// Commands are defined in the Nix config under `stackpanel.scripts` (new) or
// `devshell._commandsSerializable` (legacy). They're evaluated via nix eval
// and executed as bash scripts with the devshell environment merged in.
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
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

// ScriptArg represents a documented argument for a command
type ScriptArg struct {
	Name        string  `json:"name"`
	Description *string `json:"description"`
	Required    *bool   `json:"required"`
	Default     *string `json:"default"`
}

// SerializableCommand represents a command from the Nix config
type SerializableCommand struct {
	Name        string            `json:"name"`
	Exec        string            `json:"exec"`
	Description *string           `json:"description"`
	Env         map[string]string `json:"env"`
	Args        []ScriptArg       `json:"args"`
}

// StackpanelConfig represents the relevant parts of the serialized config
type StackpanelConfig struct {
	// New location: scripts are at the root level
	Scripts  map[string]SerializableCommand `json:"scripts"`
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
  stackpanel commands secrets:list --help  # Show help for secrets:list
  stackpanel run generate-types          # Run generate-types (using alias)
  stackpanel cmd build --release         # Run build with --release flag`,
	// Disable flag parsing so we can handle --help for subcommands ourselves
	DisableFlagParsing: true,
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()

		// Parse our own flags manually since we disabled flag parsing
		noTUI := false
		filteredArgs := []string{}
		showHelp := false

		for i := 0; i < len(args); i++ {
			arg := args[i]
			if arg == "--no-tui" {
				noTUI = true
			} else if arg == "-h" || arg == "--help" {
				showHelp = true
			} else if arg == "--" {
				// Everything after -- goes to the command
				filteredArgs = append(filteredArgs, args[i+1:]...)
				break
			} else {
				filteredArgs = append(filteredArgs, arg)
			}
		}

		// If --help with no command, show commands help
		if showHelp && len(filteredArgs) == 0 {
			cmd.Help()
			return
		}

		// Get config from nix eval
		commandsData, err := loadCommands(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to get config: %v", err))
			os.Exit(1)
		}

		// Interactive TUI when no args and TTY (unless disabled)
		if len(filteredArgs) == 0 && tui.IsInteractive() && !noTUI {
			if err := runCommandsTUI(commandsData.commands, commandsData.devshellEnv); err != nil {
				output.Error(fmt.Sprintf("Command TUI error: %v", err))
				os.Exit(1)
			}
			return
		}

		if len(filteredArgs) == 0 {
			// List commands
			listCommands(commandsData.commands)
			return
		}

		// Get the command name
		cmdName := filteredArgs[0]
		cmdArgs := filteredArgs[1:]

		// Check if this is a special subcommand like "list"
		if cmdName == "list" {
			listCommands(commandsData.commands)
			return
		}

		cmdDef, ok := commandsData.commands[cmdName]
		if !ok {
			output.Error(fmt.Sprintf("Unknown command: %s", cmdName))
			fmt.Println()
			fmt.Println("Available commands:")
			listCommands(commandsData.commands)
			os.Exit(1)
		}

		// If --help was passed, show help for this specific command
		if showHelp {
			printCommandHelp(cmdName, cmdDef)
			return
		}

		if err := runCommand(cmdDef, cmdArgs, commandsData.devshellEnv); err != nil {
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

		commandsData, err := loadCommands(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to get config: %v", err))
			os.Exit(1)
		}

		listCommands(commandsData.commands)
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

type commandsData struct {
	commands    map[string]SerializableCommand
	devshellEnv map[string]string
}

// loadCommands fetches scripts from the Nix config, preferring the new
// `scripts` location and falling back to the legacy `devshell._commandsSerializable`
// for backward compatibility with older stackpanel configs.
func loadCommands(ctx context.Context) (*commandsData, error) {
	config, err := getStackpanelConfig(ctx)
	if err != nil {
		return nil, err
	}

	commands := config.Scripts
	if len(commands) == 0 {
		commands = config.Devshell.CommandsSerializable
	}

	return &commandsData{
		commands:    commands,
		devshellEnv: config.Devshell.Env,
	}, nil
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

// printCommandHelp shows detailed help for a specific command
func printCommandHelp(name string, cmd SerializableCommand) {
	titleColor := color.New(color.FgCyan, color.Bold)
	labelColor := color.New(color.Faint)
	codeColor := color.New(color.FgGreen)
	argNameColor := color.New(color.FgYellow)
	requiredColor := color.New(color.FgRed)

	fmt.Println()
	fmt.Printf("%s\n", titleColor.Sprint(name))
	fmt.Println()

	if cmd.Description != nil && *cmd.Description != "" {
		fmt.Printf("%s\n\n", *cmd.Description)
	}

	fmt.Printf("%s\n", labelColor.Sprint("Usage:"))
	fmt.Printf("  stackpanel commands %s [args...]\n", name)
	fmt.Printf("  stackpanel run %s [args...]\n", name)
	fmt.Printf("  spx %s [args...]\n", name)
	fmt.Println()

	// Display arguments if defined
	if len(cmd.Args) > 0 {
		fmt.Printf("%s\n", labelColor.Sprint("Arguments:"))
		for _, arg := range cmd.Args {
			// Build the argument line
			argLine := "  " + argNameColor.Sprint(arg.Name)

			// Add required indicator
			if arg.Required != nil && *arg.Required {
				argLine += " " + requiredColor.Sprint("(required)")
			}

			// Add default value
			if arg.Default != nil && *arg.Default != "" {
				argLine += " " + labelColor.Sprintf("[default: %s]", *arg.Default)
			}

			fmt.Println(argLine)

			// Add description on the next line, indented
			if arg.Description != nil && *arg.Description != "" {
				fmt.Printf("      %s\n", *arg.Description)
			}
		}
		fmt.Println()
	}

	fmt.Printf("%s\n", labelColor.Sprint("Script:"))
	// Indent and display the script
	lines := strings.Split(cmd.Exec, "\n")
	for _, line := range lines {
		fmt.Printf("  %s\n", codeColor.Sprint(line))
	}
	fmt.Println()

	if len(cmd.Env) > 0 {
		fmt.Printf("%s\n", labelColor.Sprint("Environment:"))
		for k, v := range cmd.Env {
			fmt.Printf("  %s=%s\n", k, v)
		}
		fmt.Println()
	}
}

func prepareCommand(cmdDef SerializableCommand, args []string, devshellEnv map[string]string) (*exec.Cmd, string) {
	script := cmdDef.Exec

	if len(args) > 0 {
		quotedArgs := make([]string, len(args))
		for i, arg := range args {
			quotedArgs[i] = shellescape(arg)
		}
		script = script + " " + strings.Join(quotedArgs, " ")
	}

	fullScript := fmt.Sprintf("set -euo pipefail\n%s", script)

	if os.Getenv("STACKPANEL_DEBUG") != "" {
		fmt.Fprintf(os.Stderr, "[DEBUG] Executing script:\n%s\n", fullScript)
	}

	cmd := exec.Command("bash", "-c", fullScript)
	cmd.Env = os.Environ()

	for k, v := range devshellEnv {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	for k, v := range cmdDef.Env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	return cmd, fullScript
}

func runCommand(cmdDef SerializableCommand, args []string, devshellEnv map[string]string) error {
	cmd, _ := prepareCommand(cmdDef, args, devshellEnv)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}

func runCommandCaptured(cmdDef SerializableCommand, args []string, devshellEnv map[string]string) (string, error) {
	cmd, _ := prepareCommand(cmdDef, args, devshellEnv)
	cmd.Stdin = os.Stdin
	output, err := cmd.CombinedOutput()
	return string(output), err
}

// shellescape prevents shell injection when appending user-provided arguments
// to script bodies. Single-quote wrapping is the safest approach — the only
// character that needs escaping inside single quotes is the single quote itself.
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
