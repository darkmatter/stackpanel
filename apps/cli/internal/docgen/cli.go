package docgen

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"text/template"

	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
)

// CLICommandView is the view model for rendering CLI command templates
type CLICommandView struct {
	Title            string
	Description      string
	Long             string
	Usage            string
	Aliases          []string
	AliasesFormatted string
	Example          string
	Flags            []CLIFlagView
	GlobalFlags      []CLIFlagView
	Subcommands      []CLICommandSummary
	Slug             string
}

// CLIFlagView is the view model for rendering CLI flags in templates
type CLIFlagView struct {
	Name             string
	Shorthand        string
	FlagSyntax       string // e.g., "--verbose, -v" or "--config"
	Type             string
	Default          string
	DefaultFormatted string // Formatted for display (e.g., `"value"` or _none_)
	Description      string
}

// CLICommandSummary is a summary of a command for index pages
type CLICommandSummary struct {
	Name  string
	Short string
	Slug  string
}

// CLIIndexView is the view model for the CLI index page
type CLIIndexView struct {
	Commands    []CLICommandSummary
	GlobalFlags []CLIFlagView
}

// GenerateCLIDocs generates MDX documentation for CLI commands
// It takes the root cobra command and generates docs for all subcommands
func GenerateCLIDocs(rootCmd *cobra.Command, outputDir string) error {
	if rootCmd == nil {
		return fmt.Errorf("root command is nil")
	}

	// Ensure output directory exists
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create CLI docs directory: %w", err)
	}

	// Parse templates
	cliTemplates := template.Must(template.New("cli").ParseFS(templateFS,
		"templates/cli_command.mdx.tmpl",
		"templates/cli_index.mdx.tmpl",
	))

	// Collect top-level commands (excluding hidden ones)
	var commands []CLICommandSummary
	for _, cmd := range rootCmd.Commands() {
		if cmd.Hidden || cmd.Name() == "help" || cmd.Name() == "completion" {
			continue
		}
		commands = append(commands, CLICommandSummary{
			Name:  cmd.Name(),
			Short: cmd.Short,
			Slug:  cmd.Name(),
		})
	}

	// Sort commands alphabetically
	sort.Slice(commands, func(i, j int) bool {
		return commands[i].Name < commands[j].Name
	})

	// Extract global flags from root command
	globalFlags := extractFlags(rootCmd.PersistentFlags())

	// Generate index page
	indexView := CLIIndexView{
		Commands:    commands,
		GlobalFlags: globalFlags,
	}

	indexPath := filepath.Join(outputDir, "index.mdx")
	if err := renderToFile(cliTemplates, "cli_index.mdx.tmpl", indexView, indexPath); err != nil {
		return fmt.Errorf("failed to write CLI index: %w", err)
	}
	fmt.Printf("  ✓ %s\n", indexPath)

	// Generate docs for each command recursively
	for _, cmd := range rootCmd.Commands() {
		if cmd.Hidden || cmd.Name() == "help" || cmd.Name() == "completion" {
			continue
		}
		if err := generateCommandDocs(cliTemplates, cmd, outputDir, globalFlags, cmd.Name()); err != nil {
			return fmt.Errorf("failed to generate docs for %s: %w", cmd.Name(), err)
		}
	}

	fmt.Printf("\nGenerated CLI documentation for %d commands\n", len(commands))
	return nil
}

// Escape sequences that are unlikely to be actual jsx
func escapeMDX(text string) string {
	// Order matters: escape backslashes first so you don't double-escape later
	// text = strings.ReplaceAll(text, "\\", "\\\\") // Escape literal backslashes
	// text = strings.ReplaceAll(text, "{", "\\{")   // Escape JS expression braces
	// text = strings.ReplaceAll(text, "}", "\\}")
	text = strings.ReplaceAll(text, ".<", "\\<") // Escape JSX tags
	text = strings.ReplaceAll(text, ">.", "\\>")
	// text = strings.ReplaceAll(text, "*", "\\*") // Escape bold/italic
	// text = strings.ReplaceAll(text, "_", "\\_")
	// text = strings.ReplaceAll(text, "#", "\\#") // Escape headers
	// Add other characters if needed (e.g., '[', ']', '`', etc., depending on context)
	return text
}

// generateCommandDocs generates documentation for a single command and its subcommands
func generateCommandDocs(tmpl *template.Template, cmd *cobra.Command, baseDir string, inheritedFlags []CLIFlagView, pathPrefix string) error {
	// Collect subcommands
	var subcommands []CLICommandSummary
	for _, sub := range cmd.Commands() {
		if sub.Hidden || sub.Name() == "help" {
			continue
		}
		subcommands = append(subcommands, CLICommandSummary{
			Name:  sub.Name(),
			Short: sub.Short,
			Slug:  sub.Name(),
		})
	}

	// Sort subcommands
	sort.Slice(subcommands, func(i, j int) bool {
		return subcommands[i].Name < subcommands[j].Name
	})

	// Extract command-specific flags (non-persistent)
	localFlags := extractFlags(cmd.LocalNonPersistentFlags())

	// Merge inherited flags with this command's persistent flags
	persistentFlags := extractFlags(cmd.PersistentFlags())
	allInheritedFlags := mergeFlags(inheritedFlags, persistentFlags)

	// Build usage string
	usage := buildUsageString(cmd)

	// Format aliases
	aliasesFormatted := ""
	if len(cmd.Aliases) > 0 {
		aliasesFormatted = "`" + strings.Join(cmd.Aliases, "`, `") + "`"
	}

	// Get the long description, fall back to short if empty
	long := cmd.Long
	if long == "" {
		long = cmd.Short
	}

	// Create view
	view := CLICommandView{
		Title:            fmt.Sprintf("%s %s", "stackpanel", pathPrefix),
		Description:      cmd.Short,
		Long:             long,
		Usage:            usage,
		Aliases:          cmd.Aliases,
		AliasesFormatted: aliasesFormatted,
		Example:          cmd.Example,
		Flags:            localFlags,
		GlobalFlags:      allInheritedFlags,
		Subcommands:      subcommands,
		Slug:             cmd.Name(),
	}

	// Determine output path
	var outputPath string
	if len(subcommands) > 0 {
		// Command has subcommands - create a directory
		cmdDir := filepath.Join(baseDir, cmd.Name())
		if err := os.MkdirAll(cmdDir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", cmdDir, err)
		}
		outputPath = filepath.Join(cmdDir, "index.mdx")
	} else {
		// Leaf command - just create a file
		outputPath = filepath.Join(baseDir, cmd.Name()+".mdx")
	}

	if err := renderToFile(tmpl, "cli_command.mdx.tmpl", view, outputPath); err != nil {
		return err
	}
	fmt.Printf("  ✓ %s\n", outputPath)

	// Recursively generate docs for subcommands
	for _, sub := range cmd.Commands() {
		if sub.Hidden || sub.Name() == "help" {
			continue
		}
		subDir := filepath.Join(baseDir, cmd.Name())
		subPath := pathPrefix + " " + sub.Name()
		if err := generateCommandDocs(tmpl, sub, subDir, allInheritedFlags, subPath); err != nil {
			return err
		}
	}

	return nil
}

// extractFlags extracts flags from a FlagSet into CLIFlagView slice
func extractFlags(flags *pflag.FlagSet) []CLIFlagView {
	var result []CLIFlagView
	if flags == nil {
		return result
	}

	flags.VisitAll(func(f *pflag.Flag) {
		// Skip help flag as it's always present
		if f.Name == "help" {
			return
		}

		view := CLIFlagView{
			Name:        f.Name,
			Shorthand:   f.Shorthand,
			Type:        f.Value.Type(),
			Default:     f.DefValue,
			Description: f.Usage,
		}

		// Build flag syntax
		if f.Shorthand != "" {
			view.FlagSyntax = fmt.Sprintf("--%s, -%s", f.Name, f.Shorthand)
		} else {
			view.FlagSyntax = "--" + f.Name
		}

		// Format default value
		if f.DefValue == "" {
			view.DefaultFormatted = "_none_"
		} else if f.Value.Type() == "bool" && f.DefValue == "false" {
			view.DefaultFormatted = "`false`"
		} else if f.Value.Type() == "bool" && f.DefValue == "true" {
			view.DefaultFormatted = "`true`"
		} else {
			view.DefaultFormatted = fmt.Sprintf("`%s`", f.DefValue)
		}

		result = append(result, view)
	})

	// Sort flags by name
	sort.Slice(result, func(i, j int) bool {
		return result[i].Name < result[j].Name
	})

	return result
}

// mergeFlags merges two flag slices, avoiding duplicates (by name)
func mergeFlags(existing, additional []CLIFlagView) []CLIFlagView {
	seen := make(map[string]bool)
	result := make([]CLIFlagView, 0, len(existing)+len(additional))

	for _, f := range existing {
		if !seen[f.Name] {
			seen[f.Name] = true
			result = append(result, f)
		}
	}
	for _, f := range additional {
		if !seen[f.Name] {
			seen[f.Name] = true
			result = append(result, f)
		}
	}

	// Re-sort merged result
	sort.Slice(result, func(i, j int) bool {
		return result[i].Name < result[j].Name
	})

	return result
}

// buildUsageString constructs the full usage string for a command
func buildUsageString(cmd *cobra.Command) string {
	// Build from parent chain
	var parts []string
	for c := cmd; c != nil; c = c.Parent() {
		if c.Name() != "" {
			parts = append([]string{c.Name()}, parts...)
		}
	}

	usage := strings.Join(parts, " ")

	// Add the Use field's argument portion if it has arguments
	if cmd.Use != "" {
		useArgs := strings.TrimPrefix(cmd.Use, cmd.Name())
		useArgs = strings.TrimSpace(useArgs)
		if useArgs != "" {
			usage += " " + useArgs
		}
	}

	return usage
}

// renderToFile renders a template to a file
func renderToFile(tmpl *template.Template, name string, data interface{}, path string) error {
	var buf bytes.Buffer
	var safe bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, name, data); err != nil {
		return fmt.Errorf("failed to execute template %s: %w", name, err)
	}

	// escape
	safe.WriteString(escapeMDX(buf.String()))

	if err := os.WriteFile(path, safe.Bytes(), 0644); err != nil {
		return fmt.Errorf("failed to write file %s: %w", path, err)
	}

	return nil
}
