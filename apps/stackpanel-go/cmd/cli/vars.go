package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

// Variable represents a stackpanel variable from the Nix config
type Variable struct {
	ID          string   `json:"id"`
	Key         string   `json:"key"`
	Type        string   `json:"type"`
	Value       string   `json:"value"`
	Description *string  `json:"description"`
	ProvidedBy  *string  `json:"providedBy"`
	RequiredBy  []string `json:"requiredBy"`
	Ref         string   `json:"ref"`
	EnvRef      string   `json:"envRef"`
	SafeValue   string   `json:"safeValue"`
	MasterKeys  []string `json:"masterKeys"`
}

// VariablesConfig represents the variables section of the config
type VariablesConfig struct {
	Variables map[string]Variable `json:"variables"`
}

var varsCmd = &cobra.Command{
	Use:   "vars",
	Short: "Manage workspace variables",
	Long: `Manage workspace variables defined in stackpanel.

Variables can be:
  - LITERAL: Plain text values
  - SECRET: Encrypted with AGE master keys
  - VALS: External references (AWS SSM, Vault, etc.)
  - EXEC: Shell command outputs

Examples:
  stackpanel vars list              # List all variables
  stackpanel vars list --type SECRET  # List only secrets
  stackpanel vars get /apps/web/port  # Get a specific variable`,
}

var varsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all workspace variables",
	Long: `List all variables defined in stackpanel.variables.

Variables are grouped by their path prefix (e.g., /apps, /services, /dev, /prod).
Use --type to filter by variable type.`,
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()

		typeFilter, _ := cmd.Flags().GetString("type")
		jsonOutput, _ := cmd.Flags().GetBool("json")

		variables, err := loadVariables(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load variables: %v", err))
			os.Exit(1)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(variables, "", "  ")
			fmt.Println(string(data))
			return
		}

		listVariables(variables, typeFilter)
	},
}

var varsGetCmd = &cobra.Command{
	Use:   "get <variable-id>",
	Short: "Get a specific variable",
	Long: `Get details about a specific variable by its ID.

Examples:
  stackpanel vars get /apps/web/port
  stackpanel vars get /prod/postgres-url`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()

		varID := args[0]
		jsonOutput, _ := cmd.Flags().GetBool("json")

		variables, err := loadVariables(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load variables: %v", err))
			os.Exit(1)
		}

		variable, ok := variables[varID]
		if !ok {
			output.Error(fmt.Sprintf("Variable not found: %s", varID))
			os.Exit(1)
		}

		if jsonOutput {
			data, _ := json.MarshalIndent(variable, "", "  ")
			fmt.Println(string(data))
			return
		}

		printVariableDetails(varID, variable)
	},
}

func init() {
	rootCmd.AddCommand(varsCmd)
	varsCmd.AddCommand(varsListCmd)
	varsCmd.AddCommand(varsGetCmd)

	varsListCmd.Flags().StringP("type", "t", "", "Filter by type (LITERAL, SECRET, VALS, EXEC)")
	varsListCmd.Flags().Bool("json", false, "Output as JSON")
	varsGetCmd.Flags().Bool("json", false, "Output as JSON")
}

func loadVariables(ctx context.Context) (map[string]Variable, error) {
	result, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		Expression: nixeval.StackpanelSerializablePreset,
	})
	if err != nil {
		return nil, fmt.Errorf("nix eval failed: %w", err)
	}

	var config struct {
		Variables map[string]Variable `json:"variables"`
	}
	if err := json.Unmarshal(result, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	return config.Variables, nil
}

func listVariables(variables map[string]Variable, typeFilter string) {
	if len(variables) == 0 {
		output.Warning("No variables defined")
		return
	}

	// Sort variables by ID
	ids := make([]string, 0, len(variables))
	for id := range variables {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	// Group by prefix
	groups := make(map[string][]string)
	ungrouped := []string{}

	for _, id := range ids {
		v := variables[id]
		// Apply type filter
		if typeFilter != "" && !strings.EqualFold(v.Type, typeFilter) {
			continue
		}

		// Group by first path segment
		if strings.HasPrefix(id, "/") {
			parts := strings.SplitN(id[1:], "/", 2)
			if len(parts) >= 1 {
				prefix := "/" + parts[0]
				groups[prefix] = append(groups[prefix], id)
				continue
			}
		}
		ungrouped = append(ungrouped, id)
	}

	keyColor := color.New(color.FgCyan)
	typeColor := color.New(color.FgYellow)
	descColor := color.New(color.Faint)
	valueColor := color.New(color.FgGreen)
	secretColor := color.New(color.FgMagenta)

	printVar := func(id string) {
		v := variables[id]
		typeStr := typeColor.Sprintf("%-7s", v.Type)

		var valueStr string
		if v.Type == "SECRET" {
			valueStr = secretColor.Sprint("••••••••")
		} else if v.Type == "EXEC" {
			valueStr = descColor.Sprintf("$(%s)", truncate(v.Value, 30))
		} else if len(v.Value) > 40 {
			valueStr = valueColor.Sprint(truncate(v.Value, 40))
		} else {
			valueStr = valueColor.Sprint(v.Value)
		}

		fmt.Printf("  %s  %s  %s=%s\n",
			keyColor.Sprint(id),
			typeStr,
			v.Key,
			valueStr,
		)
		if v.Description != nil && *v.Description != "" {
			fmt.Printf("      %s\n", descColor.Sprint(*v.Description))
		}
	}

	// Print ungrouped first
	if len(ungrouped) > 0 {
		fmt.Println(color.New(color.Bold).Sprint("Variables:"))
		for _, id := range ungrouped {
			printVar(id)
		}
		fmt.Println()
	}

	// Print grouped
	groupNames := make([]string, 0, len(groups))
	for g := range groups {
		groupNames = append(groupNames, g)
	}
	sort.Strings(groupNames)

	for _, groupName := range groupNames {
		if len(groups[groupName]) == 0 {
			continue
		}
		fmt.Println(color.New(color.Bold).Sprintf("%s:", groupName))
		for _, id := range groups[groupName] {
			printVar(id)
		}
		fmt.Println()
	}
}

func printVariableDetails(id string, v Variable) {
	keyColor := color.New(color.FgCyan, color.Bold)
	labelColor := color.New(color.Faint)
	valueColor := color.New(color.FgGreen)
	secretColor := color.New(color.FgMagenta)

	fmt.Printf("%s\n\n", keyColor.Sprint(id))

	fmt.Printf("  %s %s\n", labelColor.Sprint("Key:"), v.Key)
	fmt.Printf("  %s %s\n", labelColor.Sprint("Type:"), v.Type)

	if v.Type == "SECRET" {
		fmt.Printf("  %s %s\n", labelColor.Sprint("Value:"), secretColor.Sprint("(encrypted)"))
		fmt.Printf("  %s %s\n", labelColor.Sprint("Master Keys:"), strings.Join(v.MasterKeys, ", "))
	} else if v.Type == "EXEC" {
		fmt.Printf("  %s %s\n", labelColor.Sprint("Command:"), v.Value)
	} else {
		fmt.Printf("  %s %s\n", labelColor.Sprint("Value:"), valueColor.Sprint(v.Value))
	}

	if v.Description != nil && *v.Description != "" {
		fmt.Printf("  %s %s\n", labelColor.Sprint("Description:"), *v.Description)
	}
	if v.ProvidedBy != nil && *v.ProvidedBy != "" {
		fmt.Printf("  %s %s\n", labelColor.Sprint("Provided By:"), *v.ProvidedBy)
	}
	if len(v.RequiredBy) > 0 {
		fmt.Printf("  %s %s\n", labelColor.Sprint("Required By:"), strings.Join(v.RequiredBy, ", "))
	}

	fmt.Println()
	fmt.Printf("  %s\n", labelColor.Sprint("Usage:"))
	fmt.Printf("    Shell:  %s\n", v.EnvRef)
	fmt.Printf("    Ref:    %s\n", v.Ref)
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}
