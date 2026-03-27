// config.go implements `stackpanel config {get,set}` for inspecting and
// modifying the Nix-evaluated project configuration. `get` evaluates a
// single attribute via `nix eval` (lazy — only the requested path is
// computed, not the full config tree). `set` patches .stack/config.nix
// through the nixdata.Store abstraction.

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
	executor "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
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
  stackpanel config get --json apps.web     # Force JSON output
  stackpanel config set apps.web.name ui    # Set a string value
  stackpanel config set ports.base 6400     # Auto-detects as number`,
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

var configSetCmd = &cobra.Command{
	Use:   "set <dot.path> <value>",
	Short: "Set a configuration value by dot-path",
	Long: `Set a value in .stack/config.nix using a dot-separated path.

Values default to auto-detection:
  - valid JSON numbers become numbers
  - true/false become booleans
  - null becomes null
  - JSON arrays/objects become list/object values
  - anything else is written as a string

Use --type to force the interpretation when needed.

Examples:
  stackpanel config set apps.docs.name docs-site
  stackpanel config set ports.base 6400
  stackpanel config set apps.docs.tls true
  stackpanel config set apps.docs.tags '["docs","public"]'
  stackpanel config set apps.docs.env.PORT var://computed/apps/docs/port --type string
  stackpanel config set apps.docs.env.API_URL 'config.variables."/dev/API_URL".value' --type nix_expr`,
	Args: cobra.ExactArgs(2),
	Run:  runConfigSet,
}

func init() {
	rootCmd.AddCommand(configCmd)
	configCmd.AddCommand(configGetCmd)
	configCmd.AddCommand(configSetCmd)

	configGetCmd.Flags().Bool("json", false, "Always output as JSON")
	configGetCmd.Flags().Bool("raw", false, "Output raw value (strip quotes from strings)")
	configGetCmd.Flags().DurationP("timeout", "t", 30*time.Second, "Nix evaluation timeout")

	configSetCmd.Flags().String("type", "auto", "Value type: auto, string, bool, number, list, object, null, nix_expr")
	configSetCmd.Flags().Bool("json", false, "Output result as JSON")
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

func runConfigSet(cmd *cobra.Command, args []string) {
	valueType, _ := cmd.Flags().GetString("type")
	jsonOutput, _ := cmd.Flags().GetBool("json")

	projectRoot, err := findProjectRoot()
	if err != nil {
		output.Error(fmt.Sprintf("Failed to find project root: %v", err))
		os.Exit(1)
	}

	configPath := nixdata.ParseConfigPath(strings.TrimSpace(args[0]))
	if configPath == "" {
		output.Error("Config path is required")
		os.Exit(1)
	}

	parsedValue, normalizedType, err := parseConfigSetValue(args[1], valueType)
	if err != nil {
		output.Error(fmt.Sprintf("Invalid value: %v", err))
		os.Exit(1)
	}

	configFilePath, err := setConfigValue(projectRoot, configPath, parsedValue)
	if err != nil {
		output.Error(fmt.Sprintf("Failed to set config value: %v", err))
		os.Exit(1)
	}

	if jsonOutput {
		data, _ := json.MarshalIndent(map[string]any{
			"path":      configPath,
			"value":     parsedValue,
			"valueType": normalizedType,
			"file":      configFilePath,
		}, "", "  ")
		fmt.Println(string(data))
		return
	}

	output.Success(fmt.Sprintf("Set %s", color.CyanString(configPath)))
	fmt.Fprintf(os.Stderr, "  %s %s\n", color.New(color.Faint).Sprint("Type:"), normalizedType)
	fmt.Fprintf(os.Stderr, "  %s %s\n", color.New(color.Faint).Sprint("File:"), configFilePath)
}

func setConfigValue(projectRoot string, configPath string, value any) (string, error) {
	exec, err := executor.NewWithoutDevshell(projectRoot, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create executor: %w", err)
	}

	store := nixdata.NewStore(projectRoot, exec)
	if err := store.PatchConsolidatedData(configPath, value); err != nil {
		return "", err
	}

	return nixdata.NewPaths(projectRoot).ConfigFilePath(), nil
}

// parseConfigSetValue interprets the user's raw string input as a typed value.
// "auto" mode tries JSON parsing first; if that fails the value is treated as
// a plain string. This lets `stackpanel config set ports.base 6400` work
// without requiring --type number, while still allowing JSON objects/arrays.
func parseConfigSetValue(raw string, valueType string) (any, string, error) {
	normalizedType := normalizeConfigValueType(valueType)

	if raw == "" && normalizedType != "string" && normalizedType != "null" {
		return nil, "", fmt.Errorf("value is required")
	}

	switch normalizedType {
	case "auto":
		var parsed any
		if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
			return raw, "string", nil
		}
		return parsed, detectJSONValueType(parsed), nil
	case "string":
		return raw, "string", nil
	case "bool":
		var b bool
		if err := json.Unmarshal([]byte(raw), &b); err != nil {
			return nil, "", fmt.Errorf("invalid bool value: %s", raw)
		}
		return b, "bool", nil
	case "number":
		var n json.Number
		if err := json.Unmarshal([]byte(raw), &n); err != nil {
			return nil, "", fmt.Errorf("invalid number value: %s", raw)
		}
		if i, err := n.Int64(); err == nil {
			return i, "number", nil
		}
		if f, err := n.Float64(); err == nil {
			return f, "number", nil
		}
		return nil, "", fmt.Errorf("invalid number value: %s", raw)
	case "list":
		var list []any
		if err := json.Unmarshal([]byte(raw), &list); err != nil {
			return nil, "", fmt.Errorf("invalid list value: %s", raw)
		}
		return list, "list", nil
	case "object":
		var obj map[string]any
		if err := json.Unmarshal([]byte(raw), &obj); err != nil {
			return nil, "", fmt.Errorf("invalid object value: %s", raw)
		}
		return obj, "object", nil
	case "null":
		return nil, "null", nil
	case "nix_expr":
		return nixdata.RawExpr(raw), "nix_expr", nil
	default:
		return nil, "", fmt.Errorf("unsupported type %q", valueType)
	}
}

func normalizeConfigValueType(valueType string) string {
	switch strings.TrimSpace(strings.ToLower(valueType)) {
	case "", "auto":
		return "auto"
	case "string", "bool", "number", "list", "object", "null":
		return strings.TrimSpace(strings.ToLower(valueType))
	case "nix-expr", "nix_expr":
		return "nix_expr"
	default:
		return strings.TrimSpace(strings.ToLower(valueType))
	}
}

func detectJSONValueType(value any) string {
	switch value.(type) {
	case nil:
		return "null"
	case bool:
		return "bool"
	case float64:
		return "number"
	case []any:
		return "list"
	case map[string]any:
		return "object"
	case string:
		return "string"
	default:
		return "string"
	}
}

// printJSON pipes raw JSON through jq for colorized, indented output.
// jq automatically disables colors when stdout is not a TTY, which is
// the right behavior for piped/scripted usage. Falls back to stdlib
// json.MarshalIndent when jq is not on PATH.
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

// printRaw outputs the value with minimal formatting — designed for
// shell scripting where you want `$(stackpanel config get project.name)`
// to produce a bare string without quotes or trailing newlines for objects.
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
