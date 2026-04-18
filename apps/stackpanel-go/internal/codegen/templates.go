// templates.go embeds and parses the TypeScript codegen templates so the
// binary is self-contained. Templates live alongside the Go sources under
// templates/ and are compiled once at init.
package codegen

import (
	"bytes"
	"embed"
	"fmt"
	"strconv"
	"text/template"
)

//go:embed templates/*.tmpl
var templateFS embed.FS

var codegenTemplates = template.Must(
	template.New("codegen").Funcs(template.FuncMap{
		// tsQuote produces a JS/TS string literal from a Go string. Go's
		// strconv.Quote uses the same escape rules as JSON, which is a strict
		// subset of valid TS, so the output is safe to drop into generated
		// modules without further escaping.
		"tsQuote": strconv.Quote,
	}).ParseFS(templateFS, "templates/*.tmpl"),
)

func renderTemplate(name string, data any) ([]byte, error) {
	var buf bytes.Buffer
	if err := codegenTemplates.ExecuteTemplate(&buf, name, data); err != nil {
		return nil, fmt.Errorf("render template %s: %w", name, err)
	}
	return buf.Bytes(), nil
}
