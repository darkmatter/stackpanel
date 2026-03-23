package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var nixifyCmd = &cobra.Command{
	Use:   "nixify <path>",
	Short: "Convert a file into a Nix file entry expression",
	Long: `Convert an existing file into a stackpanel.files.entries Nix expression.

This reads the file at the given path and produces a Nix snippet that,
when added to your stackpanel configuration, will generate an identical file.

Supported types:
  line-set   Treats each non-empty line as an entry in a deduplicated, sorted
             set (ideal for .gitignore, .dockerignore, etc.)
  json-ops   Emits path-based JSON set operations (ideal for package.json)

Examples:
  stackpanel nixify .gitignore                       # auto-detects line-set
  stackpanel nixify .gitignore --type line-set       # explicit type
  stackpanel nixify apps/web/package.json            # emits json-ops
  stackpanel nixify path/to/.dockerignore            # works for any path`,
	Args: cobra.ExactArgs(1),
	RunE: runNixify,
}

var nixifyType string

func init() {
	nixifyCmd.Flags().StringVarP(&nixifyType, "type", "t", "", "Content type (line-set). Auto-detected when omitted.")
	rootCmd.AddCommand(nixifyCmd)
}

// runNixify is the main entry point for the nixify command.
func runNixify(cmd *cobra.Command, args []string) error {
	filePath := args[0]

	// Resolve to absolute then back to repo-relative
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		return fmt.Errorf("file not found: %s", filePath)
	}

	// Determine project root so we can compute relative path for the entry key
	projectRoot, err := findProjectRoot()
	if err != nil {
		// Fall back to using the path as-given
		projectRoot = ""
	}

	entryKey := filePath
	if projectRoot != "" {
		rel, err := filepath.Rel(projectRoot, absPath)
		if err == nil {
			entryKey = rel
		}
	}

	// Auto-detect type if not specified
	fileType := nixifyType
	if fileType == "" {
		fileType = detectFileType(entryKey)
	}

	if fileType == "" {
		return fmt.Errorf("could not auto-detect type for %q; specify --type explicitly", entryKey)
	}

	switch fileType {
	case "line-set":
		return nixifyLineSet(absPath, entryKey)
	case "json-ops":
		return nixifyJSONOps(absPath, entryKey)
	default:
		return fmt.Errorf("unsupported type: %q (supported: line-set, json-ops)", fileType)
	}
}

// detectFileType guesses the nixify type from the filename.
func detectFileType(path string) string {
	base := filepath.Base(path)
	switch base {
	case "package.json":
		return "json-ops"
	case ".gitignore", ".dockerignore", ".prettierignore", ".eslintignore", ".vercelignore":
		return "line-set"
	}
	return ""
}

// nixifyLineSet reads a file and outputs a Nix line-set expression.
func nixifyLineSet(absPath string, entryKey string) error {
	f, err := os.Open(absPath)
	if err != nil {
		return fmt.Errorf("failed to open file: %w", err)
	}
	defer f.Close()

	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		// Skip empty lines and comments for the Nix representation.
		// The line-set type already handles dedup/sort, so we just
		// need the meaningful entries.
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		lines = append(lines, line)
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("failed to read file: %w", err)
	}

	if len(lines) == 0 {
		output.Warning(fmt.Sprintf("No meaningful lines found in %s", entryKey))
		return nil
	}

	// Build the Nix expression
	var b strings.Builder
	b.WriteString(fmt.Sprintf("stackpanel.files.entries.%s = {\n", nixAttrKey(entryKey)))
	b.WriteString("  type = \"line-set\";\n")
	b.WriteString("  dedupe = true;\n")
	b.WriteString("  sort = true;\n")
	b.WriteString("  lines = [\n")
	for _, line := range lines {
		b.WriteString(fmt.Sprintf("    %s\n", nixStringLiteral(line)))
	}
	b.WriteString("  ];\n")
	b.WriteString("};\n")

	fmt.Print(b.String())

	output.Success(fmt.Sprintf("Generated line-set entry for %q (%d lines)", entryKey, len(lines)))
	return nil
}

func nixifyJSONOps(absPath string, entryKey string) error {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return fmt.Errorf("failed to read file: %w", err)
	}

	var decoded any
	if err := json.Unmarshal(data, &decoded); err != nil {
		return fmt.Errorf("failed to parse json: %w", err)
	}

	ops := flattenJSONSetOps(nil, decoded)
	if len(ops) == 0 {
		output.Warning(fmt.Sprintf("No JSON fields found in %s", entryKey))
		return nil
	}

	var b strings.Builder
	b.WriteString(fmt.Sprintf("stackpanel.files.entries.%s = {\n", nixAttrKey(entryKey)))
	b.WriteString("  type = \"json-ops\";\n")
	b.WriteString("  adopt = \"backup\";\n")
	b.WriteString("  ops = [\n")
	for _, op := range ops {
		b.WriteString(fmt.Sprintf("    { op = \"set\"; path = %s; value = %s; }\n", nixPathLiteral(op.path), nixValueLiteral(op.value)))
	}
	b.WriteString("  ];\n")
	b.WriteString("};\n")

	fmt.Print(b.String())
	output.Success(fmt.Sprintf("Generated json-ops entry for %q (%d paths)", entryKey, len(ops)))
	return nil
}

type nixifySetOp struct {
	path  []string
	value any
}

func flattenJSONSetOps(prefix []string, value any) []nixifySetOp {
	switch typed := value.(type) {
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)

		var ops []nixifySetOp
		for _, key := range keys {
			ops = append(ops, flattenJSONSetOps(append(prefix, key), typed[key])...)
		}
		return ops
	default:
		return []nixifySetOp{{
			path:  append([]string(nil), prefix...),
			value: value,
		}}
	}
}

// nixStringLiteral produces a properly-escaped Nix string literal.
// Nix strings use double quotes and escape \, ", \n, \r, \t, and ${.
func nixStringLiteral(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		ch := s[i]
		switch ch {
		case '\\':
			b.WriteString(`\\`)
		case '"':
			b.WriteString(`\"`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		case '$':
			// Escape ${ to prevent Nix interpolation
			if i+1 < len(s) && s[i+1] == '{' {
				b.WriteString(`\$`)
			} else {
				b.WriteByte(ch)
			}
		default:
			b.WriteByte(ch)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// nixAttrKey returns a Nix attribute key, quoting it if it contains
// characters that aren't valid in a bare identifier.
func nixAttrKey(s string) string {
	// Nix bare identifiers: [a-zA-Z_][a-zA-Z0-9_'-]*
	// Anything else (dots, slashes, leading dot) needs quoting.
	needsQuote := false
	if len(s) == 0 {
		needsQuote = true
	} else {
		first := s[0]
		if !((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z') || first == '_') {
			needsQuote = true
		}
		if !needsQuote {
			for _, ch := range s[1:] {
				if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '\'' || ch == '-') {
					needsQuote = true
					break
				}
			}
		}
	}

	if needsQuote {
		return nixStringLiteral(s)
	}
	return s
}

func nixPathLiteral(path []string) string {
	parts := make([]string, 0, len(path))
	for _, segment := range path {
		parts = append(parts, nixStringLiteral(segment))
	}
	return fmt.Sprintf("[ %s ]", strings.Join(parts, " "))
}

func nixValueLiteral(value any) string {
	switch typed := value.(type) {
	case nil:
		return "null"
	case string:
		return nixStringLiteral(typed)
	case bool:
		if typed {
			return "true"
		}
		return "false"
	case float64:
		return strings.TrimSuffix(strings.TrimSuffix(fmt.Sprintf("%f", typed), "000000"), ".")
	case []any:
		parts := make([]string, 0, len(typed))
		for _, item := range typed {
			parts = append(parts, nixValueLiteral(item))
		}
		return fmt.Sprintf("[ %s ]", strings.Join(parts, " "))
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		var b strings.Builder
		b.WriteString("{ ")
		for _, key := range keys {
			b.WriteString(fmt.Sprintf("%s = %s; ", nixAttrKey(key), nixValueLiteral(typed[key])))
		}
		b.WriteString("}")
		return b.String()
	default:
		return fmt.Sprintf("%v", typed)
	}
}
