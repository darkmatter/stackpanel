package cmd

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/packages/stackpanel-go/envvars"
	"github.com/spf13/cobra"
)

var envCmd = &cobra.Command{
	Use:   "env",
	Short: "Manage and inspect environment variables",
	Long: `Manage and inspect Stackpanel environment variables.

This command provides tools for debugging and validating the environment
configuration used by Stackpanel.`,
}

var envListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all Stackpanel environment variables",
	Long: `List all environment variables used by Stackpanel.

By default, shows all variables with their current values. Use flags to
filter by category, source, or show only required/missing variables.`,
	Run: runEnvList,
}

var envValidateCmd = &cobra.Command{
	Use:   "validate",
	Short: "Validate required environment variables",
	Long: `Check that all required environment variables are set.

Returns a non-zero exit code if any required variables are missing.`,
	Run: runEnvValidate,
}

var envGetCmd = &cobra.Command{
	Use:   "get [NAME]",
	Short: "Get the value of an environment variable",
	Long: `Get the current value of a specific environment variable.

Also displays metadata about the variable (description, default, etc.)`,
	Args: cobra.ExactArgs(1),
	Run:  runEnvGet,
}

var envDebugCmd = &cobra.Command{
	Use:   "debug",
	Short: "Print all environment variables for debugging",
	Long: `Print a comprehensive debug view of all Stackpanel environment variables.

This is useful for troubleshooting configuration issues or verifying
the environment is set up correctly.`,
	Run: runEnvDebug,
}

// Flags
var (
	envListCategory   string
	envListSource     string
	envListRequired   bool
	envListMissing    bool
	envListShowValues bool
	envValidateStrict bool
)

func init() {
	rootCmd.AddCommand(envCmd)

	envCmd.AddCommand(envListCmd)
	envCmd.AddCommand(envValidateCmd)
	envCmd.AddCommand(envGetCmd)
	envCmd.AddCommand(envDebugCmd)

	// List command flags
	envListCmd.Flags().StringVarP(&envListCategory, "category", "c", "", "Filter by category (core, paths, agent, aws, minio, etc.)")
	envListCmd.Flags().StringVarP(&envListSource, "source", "s", "", "Filter by source (nix, dynamic, devenv)")
	envListCmd.Flags().BoolVarP(&envListRequired, "required", "r", false, "Show only required variables")
	envListCmd.Flags().BoolVarP(&envListMissing, "missing", "m", false, "Show only missing required variables")
	envListCmd.Flags().BoolVarP(&envListShowValues, "values", "V", false, "Show current values")

	// Validate command flags
	envValidateCmd.Flags().BoolVar(&envValidateStrict, "strict", false, "Exit with error if any required variable is missing")
}

func runEnvList(cmd *cobra.Command, args []string) {
	vars := envvars.All()

	// Filter by category
	if envListCategory != "" {
		category := categoryFromString(envListCategory)
		if category == "" {
			fmt.Fprintf(os.Stderr, "Unknown category: %s\n", envListCategory)
			fmt.Fprintf(os.Stderr, "Valid categories: core, paths, agent, stepca, aws, minio, services, devenv, ide\n")
			os.Exit(1)
		}
		vars = filterByCategory(vars, category)
	}

	// Filter by source
	if envListSource != "" {
		source := sourceFromString(envListSource)
		if source == "" {
			fmt.Fprintf(os.Stderr, "Unknown source: %s\n", envListSource)
			fmt.Fprintf(os.Stderr, "Valid sources: nix, dynamic, devenv\n")
			os.Exit(1)
		}
		vars = filterBySource(vars, source)
	}

	// Filter by required
	if envListRequired {
		vars = filterRequired(vars)
	}

	// Filter by missing
	if envListMissing {
		vars = filterMissing(vars)
	}

	if len(vars) == 0 {
		fmt.Println("No matching environment variables found.")
		return
	}

	// Group by category for display
	grouped := groupByCategory(vars)
	categories := sortedCategories(grouped)

	for _, cat := range categories {
		catVars := grouped[cat]
		fmt.Printf("\n%s:\n", cat)
		fmt.Println(strings.Repeat("-", len(string(cat))+1))

		for _, v := range catVars {
			status := "○"
			if v.IsSet() {
				status = "✓"
			} else if v.Required {
				status = "❌"
			}

			if envListShowValues {
				value := v.Get()
				if value == "" {
					value = "(not set)"
					if v.Default != "" {
						value = fmt.Sprintf("(default: %s)", v.Default)
					}
				} else {
					value = maskSensitive(v.Name, value)
				}
				fmt.Printf("  %s %s = %s\n", status, v.Name, value)
			} else {
				reqMark := ""
				if v.Required {
					reqMark = " [required]"
				}
				fmt.Printf("  %s %s%s\n", status, v.Name, reqMark)
			}
		}
	}
	fmt.Println()
}

func runEnvValidate(cmd *cobra.Command, args []string) {
	result := envvars.Validate()

	if len(result.Warnings) > 0 {
		fmt.Println("Warnings:")
		for _, w := range result.Warnings {
			fmt.Printf("  ⚠️  %s\n", w)
		}
		fmt.Println()
	}

	if result.Valid {
		fmt.Println("✓ All required environment variables are set.")
		return
	}

	fmt.Println("Missing required environment variables:")
	for _, v := range result.Missing {
		fmt.Printf("  ❌ %s\n", v.Name)
		fmt.Printf("     %s\n", v.Description)
		if v.Example != "" {
			fmt.Printf("     Example: %s\n", v.Example)
		}
	}

	if envValidateStrict {
		os.Exit(1)
	}
}

func runEnvGet(cmd *cobra.Command, args []string) {
	name := args[0]

	v, found := envvars.Lookup(name)
	if !found {
		fmt.Fprintf(os.Stderr, "Unknown environment variable: %s\n", name)
		os.Exit(1)
	}

	value := v.Get()

	fmt.Printf("Name:        %s\n", v.Name)
	fmt.Printf("Description: %s\n", v.Description)
	fmt.Printf("Category:    %s\n", v.Category)
	fmt.Printf("Source:      %s\n", v.Source)
	fmt.Printf("Required:    %v\n", v.Required)

	if v.Default != "" {
		fmt.Printf("Default:     %s\n", v.Default)
	}
	if v.Example != "" {
		fmt.Printf("Example:     %s\n", v.Example)
	}
	if v.GoField != "" {
		fmt.Printf("Go Field:    %s\n", v.GoField)
	}
	if v.Deprecated {
		fmt.Printf("Deprecated:  %s\n", v.DeprecationMessage)
	}

	fmt.Println()

	if value != "" {
		fmt.Printf("Current Value: %s\n", maskSensitive(v.Name, value))
	} else if v.Default != "" {
		fmt.Printf("Current Value: (not set, default: %s)\n", v.Default)
	} else {
		fmt.Printf("Current Value: (not set)\n")
	}
}

func runEnvDebug(cmd *cobra.Command, args []string) {
	envvars.PrintDebug()
}

// Helper functions

func categoryFromString(s string) envvars.Category {
	switch strings.ToLower(s) {
	case "core":
		return envvars.CategoryCore
	case "paths":
		return envvars.CategoryPaths
	case "agent":
		return envvars.CategoryAgent
	case "stepca", "step":
		return envvars.CategoryStepCA
	case "aws":
		return envvars.CategoryAWS
	case "minio":
		return envvars.CategoryMinio
	case "services":
		return envvars.CategoryServices
	case "devenv":
		return envvars.CategoryDevenv
	case "ide":
		return envvars.CategoryIDE
	default:
		return ""
	}
}

func sourceFromString(s string) envvars.Source {
	switch strings.ToLower(s) {
	case "nix":
		return envvars.SourceNix
	case "dynamic":
		return envvars.SourceDynamic
	case "devenv":
		return envvars.SourceDevenv
	default:
		return ""
	}
}

func filterByCategory(vars []envvars.EnvVar, category envvars.Category) []envvars.EnvVar {
	var result []envvars.EnvVar
	for _, v := range vars {
		if v.Category == category {
			result = append(result, v)
		}
	}
	return result
}

func filterBySource(vars []envvars.EnvVar, source envvars.Source) []envvars.EnvVar {
	var result []envvars.EnvVar
	for _, v := range vars {
		if v.Source == source {
			result = append(result, v)
		}
	}
	return result
}

func filterRequired(vars []envvars.EnvVar) []envvars.EnvVar {
	var result []envvars.EnvVar
	for _, v := range vars {
		if v.Required {
			result = append(result, v)
		}
	}
	return result
}

func filterMissing(vars []envvars.EnvVar) []envvars.EnvVar {
	var result []envvars.EnvVar
	for _, v := range vars {
		if v.Required && !v.IsSet() {
			result = append(result, v)
		}
	}
	return result
}

func groupByCategory(vars []envvars.EnvVar) map[envvars.Category][]envvars.EnvVar {
	result := make(map[envvars.Category][]envvars.EnvVar)
	for _, v := range vars {
		result[v.Category] = append(result[v.Category], v)
	}
	return result
}

func sortedCategories(grouped map[envvars.Category][]envvars.EnvVar) []envvars.Category {
	// Define the order we want categories to appear
	order := []envvars.Category{
		envvars.CategoryCore,
		envvars.CategoryPaths,
		envvars.CategoryAgent,
		envvars.CategoryStepCA,
		envvars.CategoryAWS,
		envvars.CategoryMinio,
		envvars.CategoryServices,
		envvars.CategoryDevenv,
		envvars.CategoryIDE,
	}

	var result []envvars.Category
	for _, cat := range order {
		if _, exists := grouped[cat]; exists {
			result = append(result, cat)
		}
	}

	// Add any categories not in our predefined order
	for cat := range grouped {
		found := false
		for _, c := range order {
			if c == cat {
				found = true
				break
			}
		}
		if !found {
			result = append(result, cat)
		}
	}

	// Sort the additional categories alphabetically
	if len(result) > len(order) {
		extra := result[len(order):]
		sort.Slice(extra, func(i, j int) bool {
			return string(extra[i]) < string(extra[j])
		})
	}

	return result
}

func maskSensitive(name, value string) string {
	nameLower := strings.ToLower(name)
	if strings.Contains(nameLower, "secret") ||
		strings.Contains(nameLower, "password") ||
		strings.Contains(nameLower, "token") ||
		strings.Contains(nameLower, "key") {
		if len(value) > 8 {
			return value[:4] + "****" + value[len(value)-4:]
		}
		return "****"
	}
	return value
}
