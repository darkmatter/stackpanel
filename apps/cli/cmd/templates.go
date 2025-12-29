package cmd

import (
	"bytes"
	"embed"
	"strings"
	"text/template"
)

// escapeYAMLString escapes a string for use in a YAML value
func escapeYAMLString(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "\"", "\\\"")
	return "\"" + s + "\""
}

//go:embed templates/*.tmpl
var templateFS embed.FS

var templates *template.Template

func init() {
	var err error
	templates, err = template.ParseFS(templateFS, "templates/*.tmpl")
	if err != nil {
		panic("failed to parse embedded templates: " + err.Error())
	}
}

// CategoryData holds data for category.mdx.tmpl
type CategoryData struct {
	Title    string
	Category string
	Icon     string
}

// IndexData holds data for index.mdx.tmpl
type IndexData struct {
	CategoryLinks string
}

// ModuleData holds data for module.mdx.tmpl
type ModuleData struct {
	Title       string
	Description string
	Icon        string
	Content     string
}

// ModulesIndexData holds data for modules_index.mdx.tmpl
type ModulesIndexData struct {
	ModuleLinks string
}

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
