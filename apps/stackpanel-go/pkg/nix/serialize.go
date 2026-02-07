// Package nix provides utilities for serializing Go values to Nix expressions.
package nix

import (
	"bytes"
	"fmt"
	"os/exec"
	"reflect"
	"sort"
	"strconv"
	"strings"
)

// Serialize converts a Go value to a valid Nix expression string.
// Supported types:
//   - nil → null
//   - bool → true/false
//   - int, int8, int16, int32, int64 → integer literal
//   - uint, uint8, uint16, uint32, uint64 → integer literal
//   - float32, float64 → float literal
//   - string → quoted string with proper escaping
//   - []T → [ ... ]
//   - map[string]T → { key = value; ... }
//   - struct → { field = value; ... } (uses json tags for field names)
//   - *T → unwraps pointer, nil pointer becomes null
func Serialize(v any) (string, error) {
	return serializeValue(reflect.ValueOf(v), 0)
}

// SerializeIndented converts a Go value to a formatted Nix expression with indentation.
func SerializeIndented(v any, indent string) (string, error) {
	s, err := serializeValue(reflect.ValueOf(v), 0)
	if err != nil {
		return "", err
	}
	return formatNix(s, indent), nil
}

// SerializeWithSections converts a Go map to a formatted Nix attrset with section comments.
// The sectionHeaders map provides human-readable headers for top-level keys.
// Keys not in sectionHeaders will not have comments.
func SerializeWithSections(v any, indent string, sectionHeaders map[string]string) (string, error) {
	// Get the underlying map
	rv := reflect.ValueOf(v)
	for rv.Kind() == reflect.Ptr || rv.Kind() == reflect.Interface {
		if rv.IsNil() {
			return "{ }\n", nil
		}
		rv = rv.Elem()
	}

	if rv.Kind() != reflect.Map {
		// Not a map, fall back to regular serialization
		return SerializeIndented(v, indent)
	}

	if rv.Type().Key().Kind() != reflect.String {
		return "", fmt.Errorf("map keys must be strings, got %s", rv.Type().Key().Kind())
	}

	if rv.Len() == 0 {
		return "{ }\n", nil
	}

	// Sort keys for deterministic output
	keys := rv.MapKeys()
	sort.Slice(keys, func(i, j int) bool {
		return keys[i].String() < keys[j].String()
	})

	var b strings.Builder
	b.WriteString("{\n")

	for _, key := range keys {
		keyStr := key.String()
		val, err := serializeValue(rv.MapIndex(key), 1)
		if err != nil {
			return "", fmt.Errorf("map key %q: %w", keyStr, err)
		}

		// Add section header comment if defined
		if header, ok := sectionHeaders[keyStr]; ok {
			b.WriteString(indent)
			b.WriteString("# ---------------------------------------------------------------------------\n")
			b.WriteString(indent)
			b.WriteString("# ")
			b.WriteString(header)
			b.WriteString("\n")
			b.WriteString(indent)
			b.WriteString("# ---------------------------------------------------------------------------\n")
		}

		// Write the key-value pair
		b.WriteString(indent)
		b.WriteString(serializeAttrName(keyStr))
		b.WriteString(" = ")
		b.WriteString(val)
		b.WriteString(";\n\n")
	}

	b.WriteString("}\n")

	// Format with nixfmt
	return formatNix(b.String(), indent), nil
}

func serializeValue(v reflect.Value, depth int) (string, error) {
	// Handle invalid (nil interface)
	if !v.IsValid() {
		return "null", nil
	}

	// Unwrap pointers
	for v.Kind() == reflect.Ptr || v.Kind() == reflect.Interface {
		if v.IsNil() {
			return "null", nil
		}
		v = v.Elem()
	}

	switch v.Kind() {
	case reflect.Bool:
		if v.Bool() {
			return "true", nil
		}
		return "false", nil

	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return strconv.FormatInt(v.Int(), 10), nil

	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return strconv.FormatUint(v.Uint(), 10), nil

	case reflect.Float32, reflect.Float64:
		f := v.Float()
		// Check if this float is actually a whole number (common when JSON decodes integers as float64)
		if f == float64(int64(f)) {
			// It's a whole number, serialize as integer to avoid "1.0" in Nix
			return strconv.FormatInt(int64(f), 10), nil
		}
		// Nix requires floats to have a decimal point
		s := strconv.FormatFloat(f, 'f', -1, 64)
		if !strings.Contains(s, ".") {
			s += ".0"
		}
		return s, nil

	case reflect.String:
		return serializeString(v.String()), nil

	case reflect.Slice, reflect.Array:
		return serializeSlice(v, depth)

	case reflect.Map:
		return serializeMap(v, depth)

	case reflect.Struct:
		return serializeStruct(v, depth)

	default:
		return "", fmt.Errorf("unsupported type: %s", v.Kind())
	}
}

// serializeString properly escapes a string for Nix.
// Uses double quotes for simple strings, or ” for multiline.
func serializeString(s string) string {
	// Check if multiline
	if strings.Contains(s, "\n") {
		return serializeMultilineString(s)
	}
	return serializeSimpleString(s)
}

// serializeSimpleString escapes a single-line string for Nix double quotes.
func serializeSimpleString(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '\\':
			b.WriteString("\\\\")
		case '"':
			b.WriteString("\\\"")
		case '\n':
			b.WriteString("\\n")
		case '\r':
			b.WriteString("\\r")
		case '\t':
			b.WriteString("\\t")
		case '$':
			// Escape $ to prevent interpolation
			b.WriteString("\\$")
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// serializeMultilineString uses Nix's ” syntax for multiline strings.
func serializeMultilineString(s string) string {
	var b strings.Builder
	b.WriteString("''")
	for _, r := range s {
		switch r {
		case '$':
			// Escape ${ interpolation
			b.WriteString("''$")
		case '\'':
			// Escape '' by using '''
			b.WriteString("'''")
		default:
			b.WriteRune(r)
		}
	}
	b.WriteString("''")
	return b.String()
}

func serializeSlice(v reflect.Value, depth int) (string, error) {
	if v.Len() == 0 {
		return "[ ]", nil
	}

	var parts []string
	for i := 0; i < v.Len(); i++ {
		elem, err := serializeValue(v.Index(i), depth+1)
		if err != nil {
			return "", fmt.Errorf("slice index %d: %w", i, err)
		}
		parts = append(parts, elem)
	}

	return "[ " + strings.Join(parts, " ") + " ]", nil
}

func serializeMap(v reflect.Value, depth int) (string, error) {
	if v.Type().Key().Kind() != reflect.String {
		return "", fmt.Errorf("map keys must be strings, got %s", v.Type().Key().Kind())
	}

	if v.Len() == 0 {
		return "{ }", nil
	}

	// Sort keys for deterministic output
	keys := v.MapKeys()
	sort.Slice(keys, func(i, j int) bool {
		return keys[i].String() < keys[j].String()
	})

	var parts []string
	for _, key := range keys {
		keyStr := key.String()
		val, err := serializeValue(v.MapIndex(key), depth+1)
		if err != nil {
			return "", fmt.Errorf("map key %q: %w", keyStr, err)
		}
		parts = append(parts, fmt.Sprintf("%s = %s;", serializeAttrName(keyStr), val))
	}

	return "{ " + strings.Join(parts, " ") + " }", nil
}

func serializeStruct(v reflect.Value, depth int) (string, error) {
	t := v.Type()
	var parts []string

	for i := 0; i < v.NumField(); i++ {
		field := t.Field(i)
		fieldVal := v.Field(i)

		// Skip unexported fields
		if !field.IsExported() {
			continue
		}

		// Get field name from json tag, or use field name
		name := field.Name
		if tag := field.Tag.Get("json"); tag != "" {
			tagParts := strings.Split(tag, ",")
			if tagParts[0] == "-" {
				continue // Skip this field
			}
			if tagParts[0] != "" {
				name = tagParts[0]
			}
			// Handle omitempty
			if len(tagParts) > 1 && tagParts[1] == "omitempty" {
				if isZero(fieldVal) {
					continue
				}
			}
		}

		val, err := serializeValue(fieldVal, depth+1)
		if err != nil {
			return "", fmt.Errorf("struct field %s: %w", name, err)
		}
		parts = append(parts, fmt.Sprintf("%s = %s;", serializeAttrName(name), val))
	}

	if len(parts) == 0 {
		return "{ }", nil
	}

	return "{ " + strings.Join(parts, " ") + " }", nil
}

// serializeAttrName quotes an attribute name if needed.
// Nix attr names can be unquoted if they match [a-zA-Z_][a-zA-Z0-9_'-]*
func serializeAttrName(name string) string {
	if isValidIdentifier(name) {
		return name
	}
	return serializeSimpleString(name)
}

// isValidIdentifier checks if a string is a valid unquoted Nix identifier.
func isValidIdentifier(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		if i == 0 {
			if !isIdentStart(r) {
				return false
			}
		} else {
			if !isIdentChar(r) {
				return false
			}
		}
	}
	return true
}

func isIdentStart(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_'
}

func isIdentChar(r rune) bool {
	return isIdentStart(r) || (r >= '0' && r <= '9') || r == '-' || r == '\''
}

func isZero(v reflect.Value) bool {
	switch v.Kind() {
	case reflect.Ptr, reflect.Interface, reflect.Slice, reflect.Map, reflect.Chan, reflect.Func:
		return v.IsNil()
	default:
		return v.IsZero()
	}
}

// formatNix formats a Nix expression using nixfmt-rfc-style if available,
// otherwise falls back to a simple indentation-based formatter.
func formatNix(s string, indent string) string {
	if indent == "" {
		return s
	}

	// Try to use nixfmt-rfc-style for proper formatting
	if formatted, err := formatWithNixfmt(s); err == nil {
		return formatted
	}

	// Fallback to simple formatter
	return formatNixSimple(s, indent)
}

// formatWithNixfmt uses the external nixfmt-rfc-style command to format Nix code.
func formatWithNixfmt(s string) (string, error) {
	// Try nixfmt-rfc-style first (newer name), then nixfmt
	for _, cmd := range []string{"nixfmt"} {
		formatted, err := runFormatter(cmd, s)
		if err == nil {
			return formatted, nil
		}
	}
	return "", fmt.Errorf("no nix formatter available")
}

// runFormatter runs an external formatter command.
func runFormatter(cmdName string, input string) (string, error) {
	cmd := exec.Command(cmdName)
	cmd.Stdin = strings.NewReader(input)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("%s failed: %w: %s", cmdName, err, stderr.String())
	}

	return stdout.String(), nil
}

// formatNixSimple is a simple fallback formatter that indents based on braces.
// It's less accurate than nixfmt but doesn't require external tools.
func formatNixSimple(s string, indent string) string {
	var b strings.Builder
	depth := 0
	inString := false
	stringChar := byte(0)
	prevChar := byte(0)

	for i := 0; i < len(s); i++ {
		c := s[i]

		// Track string state
		if !inString {
			if c == '"' {
				inString = true
				stringChar = '"'
			} else if c == '\'' && i+1 < len(s) && s[i+1] == '\'' {
				inString = true
				stringChar = '\''
				b.WriteByte(c)
				i++
				c = s[i]
			}
		} else {
			if stringChar == '"' && c == '"' && prevChar != '\\' {
				inString = false
			} else if stringChar == '\'' && c == '\'' && i+1 < len(s) && s[i+1] == '\'' && prevChar != '\'' {
				inString = false
				b.WriteByte(c)
				i++
				c = s[i]
			}
		}

		if inString {
			b.WriteByte(c)
			prevChar = c
			continue
		}

		switch c {
		case '{', '[':
			b.WriteByte(c)
			// Check if next non-space char is closing brace
			j := i + 1
			for j < len(s) && s[j] == ' ' {
				j++
			}
			if j < len(s) && (s[j] == '}' || s[j] == ']') {
				// Empty braces, skip to closing
				b.WriteByte(' ')
				i = j - 1
			} else {
				depth++
				b.WriteByte('\n')
				b.WriteString(strings.Repeat(indent, depth))
			}
		case '}', ']':
			depth--
			if depth < 0 {
				depth = 0
			}
			b.WriteByte('\n')
			b.WriteString(strings.Repeat(indent, depth))
			b.WriteByte(c)
		case ';':
			b.WriteByte(c)
			// Check if next char is not a closing brace
			j := i + 1
			for j < len(s) && s[j] == ' ' {
				j++
			}
			if j < len(s) && s[j] != '}' && s[j] != ']' {
				b.WriteByte('\n')
				b.WriteString(strings.Repeat(indent, depth))
				i = j - 1
			}
		case ' ':
			// Collapse multiple spaces outside of significant positions
			if prevChar != ' ' && prevChar != '\n' && prevChar != '{' && prevChar != '[' {
				b.WriteByte(c)
			}
		default:
			b.WriteByte(c)
		}
		prevChar = c
	}

	return b.String()
}
