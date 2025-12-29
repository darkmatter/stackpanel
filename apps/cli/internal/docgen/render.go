package docgen

import (
	"bytes"
	"embed"
	"text/template"
)

// Data structures for templates
type CategoryData struct {
	Title    string
	Category string
	Icon     string
}

type IndexData struct {
	CategoryLinks string
}

type ModuleData struct {
	Title       string
	Description string
	Icon        string
	Content     string
}

type ModulesIndexData struct {
	ModuleLinks string
}

//go:embed templates/*.tmpl
var templateFS embed.FS

var templates = template.Must(template.New("").ParseFS(templateFS, "templates/*.mdx.tmpl"))

// renderTemplate renders a template by name with the given data
func renderTemplate(name string, data interface{}) (string, error) {
	var buf bytes.Buffer
	if err := templates.ExecuteTemplate(&buf, name, data); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// RenderCategoryHeader renders the category page header
func RenderCategoryHeader(title, category, icon string) (string, error) {
	return renderTemplate("category.mdx.tmpl", CategoryData{
		Title:    title,
		Category: category,
		Icon:     icon,
	})
}

// RenderIndex renders the options index page
func RenderIndex(categoryLinks string) (string, error) {
	return renderTemplate("index.mdx.tmpl", IndexData{
		CategoryLinks: categoryLinks,
	})
}

// RenderModule renders a module documentation page
func RenderModule(title, description, icon, content string) (string, error) {
	return renderTemplate("module.mdx.tmpl", ModuleData{
		Title:       escapeYAMLString(title),
		Description: escapeYAMLString(description),
		Icon:        icon,
		Content:     content,
	})
}

// RenderModulesIndex renders the modules index page
func RenderModulesIndex(moduleLinks string) (string, error) {
	return renderTemplate("modules_index.mdx.tmpl", ModulesIndexData{
		ModuleLinks: moduleLinks,
	})
}
