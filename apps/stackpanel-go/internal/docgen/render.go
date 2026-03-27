package docgen

import (
	"bytes"
	"embed"
	"text/template"
)

// Template data types for the embedded MDX templates.
// Each type corresponds to one .mdx.tmpl file and contains the variables
// that template expects.

// CategoryData provides variables for the Nix options category page template.
type CategoryData struct {
	Title    string
	Category string
	Icon     string // Lucide icon name for Fumadocs
}

// IndexData provides variables for the options reference index page template.
type IndexData struct {
	CategoryLinks string // Pre-rendered markdown link list
}

// ModuleData provides variables for the module documentation page template.
type ModuleData struct {
	Title       string
	Description string
	Icon        string // Lucide icon name; empty string omits the icon from frontmatter
	Content     string // Markdown body content (H1 already stripped)
}

// ModulesIndexData provides variables for the modules index page template.
type ModulesIndexData struct {
	ModuleLinks string // Pre-rendered markdown link list
}

//go:embed templates/*.tmpl
var templateFS embed.FS

// templates holds the parsed MDX templates. Parsed once at init time via
// embed.FS so template files are compiled into the binary.
var templates = template.Must(template.New("").ParseFS(templateFS, "templates/*.mdx.tmpl"))

// renderTemplate renders a template by name with the given data
func renderTemplate(name string, data interface{}) (string, error) {
	var buf bytes.Buffer
	if err := templates.ExecuteTemplate(&buf, name, data); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// RenderCategoryHeader renders the frontmatter and header for a Nix options
// category page (e.g., the "Apps" or "Services" reference page).
func RenderCategoryHeader(title, category, icon string) (string, error) {
	return renderTemplate("category.mdx.tmpl", CategoryData{
		Title:    title,
		Category: category,
		Icon:     icon,
	})
}

// RenderIndex renders the top-level options reference index page.
func RenderIndex(categoryLinks string) (string, error) {
	return renderTemplate("index.mdx.tmpl", IndexData{
		CategoryLinks: categoryLinks,
	})
}

// RenderModule renders a module documentation page. Title and description are
// YAML-escaped before insertion into frontmatter.
func RenderModule(title, description, icon, content string) (string, error) {
	return renderTemplate("module.mdx.tmpl", ModuleData{
		Title:       escapeYAMLString(title),
		Description: escapeYAMLString(description),
		Icon:        icon,
		Content:     content,
	})
}

// RenderModulesIndex renders the modules section index page.
func RenderModulesIndex(moduleLinks string) (string, error) {
	return renderTemplate("modules_index.mdx.tmpl", ModulesIndexData{
		ModuleLinks: moduleLinks,
	})
}
