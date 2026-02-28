package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Inspect the stackpanel configuration",
	Long: `Inspect and query the stackpanel configuration.

The configuration is evaluated from the flake output (.#stackpanelConfig)
and includes all computed values from Nix modules.

Examples:
  stackpanel config get                     # Print entire config
  stackpanel config get project.name        # Get the project name
  stackpanel config get apps.web.port       # Get a nested value
  stackpanel config get devshell.env        # Get an object as JSON
  stackpanel config get --json apps.web     # Force JSON output`,
}

var configGetCmd = &cobra.Command{
	Use:   "get [dot.path]",
	Short: "Get a configuration value by dot-path",
	Long: `Get a value from the stackpanel configuration using a dot-separated path.

Without a path, prints the entire configuration. With a path, traverses
into the config and prints the value at that location.

Scalar values (strings, numbers, booleans) are printed raw by default.
Objects and arrays are printed as colorized JSON (via jq when available,
plain JSON otherwise). Use --json to always get JSON output, or --raw to
suppress any formatting.

The lookup is performed directly by Nix evaluation, so only the requested
attribute is evaluated — not the entire config tree.

Examples:
  stackpanel config get                           # Entire config as JSON
  stackpanel config get project.name              # my-project
  stackpanel config get apps.web.port             # 3000
  stackpanel config get apps                      # { "web": { ... }, ... }
  stackpanel config get apps.web.port --json      # 3000 (as JSON)
  stackpanel config get project.name --raw        # my-project (no quotes)`,
	Args: cobra.MaximumNArgs(1),
	Run:  runConfigGet,
}

func init() {
	rootCmd.AddCommand(configCmd)
	configCmd.AddCommand(configGetCmd)

	configGetCmd.Flags().Bool("json", false, "Always output as JSON")
	configGetCmd.Flags().Bool("raw", false, "Output raw value (strip quotes from strings)")
	configGetCmd.Flags().DurationP("timeout", "t", 30*time.Second, "Nix evaluation timeout")
}

func runConfigGet(cmd *cobra.Command, args []string) {
	jsonOutput, _ := cmd.Flags().GetBool("json")
	rawOutput, _ := cmd.Flags().GetBool("raw")
	timeout, _ := cmd.Flags().GetDuration("timeout")

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	// Build the flake attribute path
	attrPath := nixeval.StackpanelSerializablePreset // .#stackpanelConfig
	dotPath := ""
	if len(args) == 1 && args[0] != "" {
		dotPath = args[0]
		// Convert dot.path to Nix attribute path: .#stackpanelConfig.dot.path
		attrPath = attrPath + "." + dotPath
	}

	result, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		Expression: attrPath,
	})
	if err != nil {
		errMsg := err.Error()

		// Provide a friendlier message for missing attributes
		if strings.Contains(errMsg, "does not exist") ||
			strings.Contains(errMsg, "is not a set") ||
			strings.Contains(errMsg, "missing attribute") {
			if dotPath != "" {
				output.Error(fmt.Sprintf("Path not found: %s", color.CyanString(dotPath)))
				// Try to suggest the parent path
				if lastDot := strings.LastIndex(dotPath, "."); lastDot > 0 {
					parentPath := dotPath[:lastDot]
					fmt.Fprintf(os.Stderr, "\n  Try listing the parent:\n")
					fmt.Fprintf(os.Stderr, "    %s\n\n",
						color.New(color.Faint).Sprintf("stackpanel config get %s", parentPath))
				} else {
					fmt.Fprintf(os.Stderr, "\n  Try listing all top-level keys:\n")
					fmt.Fprintf(os.Stderr, "    %s\n\n",
						color.New(color.Faint).Sprint("stackpanel config get"))
				}
			} else {
				output.Error("Failed to evaluate config")
				fmt.Fprintf(os.Stderr, "\n  %s\n\n", color.New(color.Faint).Sprint(errMsg))
			}
			os.Exit(1)
		}

		output.Error(fmt.Sprintf("Failed to evaluate config: %v", err))
		os.Exit(1)
	}

	// Parse the raw JSON to determine the value type
	var value any
	if err := json.Unmarshal(result, &value); err != nil {
		// If we can't parse it as JSON, print it raw (shouldn't happen with nix eval --json)
		fmt.Print(string(result))
		return
	}

	// Determine output format
	if jsonOutput {
		printJSON(result)
		return
	}

	if rawOutput {
		printRaw(value)
		return
	}

	// Default: raw for scalars, colorized JSON for structured types
	switch v := value.(type) {
	case string:
		fmt.Println(v)
	case float64:
		// Print integers without decimal point
		if v == float64(int64(v)) {
			fmt.Println(int64(v))
		} else {
			fmt.Println(v)
		}
	case bool:
		fmt.Println(v)
	case nil:
		fmt.Println("null")
	default:
		// Objects and arrays get colorized JSON via jq
		printJSON(result)
	}
}

// printJSON pipes raw JSON through jq for colorized, indented output.
// Falls back to plain json.MarshalIndent when jq is not available.
// jq automatically disables colors when stdout is not a TTY.
func printJSON(raw []byte) {
	jqPath, err := exec.LookPath("jq")
	if err == nil {
		cmd := exec.Command(jqPath, ".")
		cmd.Stdin = strings.NewReader(string(raw))
		cmd.Stdout = os.Stdout
		cmd.Stderr = nil
		if cmd.Run() == nil {
			return
		}
	}

	// Fallback: re-indent without color
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		os.Stdout.Write(raw)
		fmt.Println()
		return
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		os.Stdout.Write(raw)
		fmt.Println()
		return
	}
	fmt.Println(string(data))
}

// printRaw outputs the value with minimal formatting — strings have no
// quotes, numbers and booleans are printed as-is, and structured types
// are compacted onto one line.
func printRaw(value any) {
	switch v := value.(type) {
	case string:
		fmt.Print(v)
	case float64:
		if v == float64(int64(v)) {
			fmt.Print(int64(v))
		} else {
			fmt.Print(v)
		}
	case bool:
		fmt.Print(v)
	case nil:
		// Print nothing for null in raw mode
	default:
		data, err := json.Marshal(value)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to format value: %v", err))
			os.Exit(1)
		}
		fmt.Print(string(data))
	}
}
