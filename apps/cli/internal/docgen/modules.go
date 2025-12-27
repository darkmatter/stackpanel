package docgen

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// generateModuleDocs generates MDX docs from README files and .nix headers in module directories
func generateModuleDocs(modulesDir string, outputDir string) ([]string, error) {
	// Find README.md files
	readmeFiles, err := findReadmeFiles(modulesDir, modulesDir)
	if err != nil {
		return nil, err
	}

	// Find .nix files with doc headers
	nixDocFiles, err := findNixDocHeaders(modulesDir, modulesDir)
	if err != nil {
		return nil, err
	}

	// Combine and deduplicate (README takes precedence)
	seenModules := make(map[string]bool)
	var allDocs []DocSource

	for _, rf := range readmeFiles {
		seenModules[rf.RelativePath] = true
		allDocs = append(allDocs, rf)
	}

	for _, nf := range nixDocFiles {
		if !seenModules[nf.RelativePath] {
			allDocs = append(allDocs, nf)
		}
	}

	var generatedModules []string

	if len(allDocs) == 0 {
		fmt.Println("No documentation sources found in modules directory")
		return generatedModules, nil
	}

	// Create modules output directory
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return nil, err
	}

	fmt.Println("\n📖 Generating module documentation...")

	// Parse all docs and extract frontmatter to determine output paths
	var parsedDocs []ParsedDoc
	for _, doc := range allDocs {
		content, err := os.ReadFile(doc.Path)
		if err != nil {
			return nil, fmt.Errorf("failed to read %s: %w", doc.Path, err)
		}

		var fm Frontmatter
		var docContent string

		if doc.IsNixFile {
			rawContent := extractNixDocHeader(doc.Path)
			fm, docContent = parseNixDocDirectives(rawContent)
		} else {
			fm, docContent = parseFrontmatter(string(content))
		}

		// Skip docs marked with skip directive
		if fm.Skip {
			fmt.Printf("  ⊘ %s (skipped)\n", doc.Path)
			continue
		}

		// Determine output path: use frontmatter output if specified, otherwise default
		outputPath := filepath.Join(outputDir, doc.RelativePath+".mdx")
		if fm.Output != "" {
			// Output is relative to the docs directory (parent of outputDir)
			docsBaseDir := filepath.Dir(outputDir)
			outputPath = filepath.Join(docsBaseDir, fm.Output)
			// Ensure .mdx extension
			if !strings.HasSuffix(outputPath, ".mdx") {
				outputPath += ".mdx"
			}
		}

		parsedDocs = append(parsedDocs, ParsedDoc{
			Source:      doc,
			Frontmatter: fm,
			Content:     docContent,
			OutputPath:  outputPath,
		})
	}

	// Group docs by output path for concatenation
	outputGroups := make(map[string][]ParsedDoc)
	for _, pd := range parsedDocs {
		outputGroups[pd.OutputPath] = append(outputGroups[pd.OutputPath], pd)
	}

	// Generate output files
	for outputPath, docs := range outputGroups {
		var mdxContent string

		if len(docs) == 1 {
			// Single doc, use normal conversion
			doc := docs[0]
			if doc.Source.IsNixFile {
				mdxContent = convertNixHeaderToMdx(doc.Content, doc.Source.ModuleName)
			} else {
				// Re-add frontmatter for conversion since we already parsed it
				mdxContent = convertDocToMdxWithFrontmatter(doc.Frontmatter, doc.Content, doc.Source.ModuleName)
			}
		} else {
			// Multiple docs targeting same output - concatenate
			mdxContent = concatenateDocsToMdx(docs)
		}

		// Create subdirectory structure if needed
		outputDirForFile := filepath.Dir(outputPath)
		if err := os.MkdirAll(outputDirForFile, 0755); err != nil {
			return nil, err
		}

		if err := os.WriteFile(outputPath, []byte(mdxContent), 0644); err != nil {
			return nil, fmt.Errorf("failed to write %s: %w", outputPath, err)
		}

		if len(docs) > 1 {
			fmt.Printf("  ✓ %s (merged from %d sources)\n", outputPath, len(docs))
		} else {
			sourceType := "README"
			if docs[0].Source.IsNixFile {
				sourceType = "nix"
			}
			fmt.Printf("  ✓ %s (%s)\n", outputPath, sourceType)
		}

		for _, doc := range docs {
			generatedModules = append(generatedModules, doc.Source.ModuleName)
		}
	}

	// Generate modules index (only for docs without custom output)
	var indexDocs []DocSource
	for _, pd := range parsedDocs {
		if pd.Frontmatter.Output == "" {
			indexDocs = append(indexDocs, pd.Source)
		}
	}

	if len(indexDocs) > 0 {
		modulesIndexPath := filepath.Join(outputDir, "index.mdx")
		modulesIndex := generateModulesIndexMdx(indexDocs)
		if err := os.WriteFile(modulesIndexPath, []byte(modulesIndex), 0644); err != nil {
			return nil, err
		}
		fmt.Printf("  ✓ %s\n", modulesIndexPath)
	}

	return generatedModules, nil
}

// generateModulesIndexMdx generates the index page for modules
func generateModulesIndexMdx(docSources []DocSource) string {
	// Sort by module name
	sort.Slice(docSources, func(i, j int) bool {
		return docSources[i].ModuleName < docSources[j].ModuleName
	})

	var moduleLinks strings.Builder
	for _, ds := range docSources {
		title := strings.ToUpper(ds.ModuleName[:1]) + ds.ModuleName[1:]
		moduleLinks.WriteString(fmt.Sprintf("  - [%s](./%s)\n", title, ds.RelativePath))
	}

	result, err := RenderModulesIndex(moduleLinks.String())
	if err != nil {
		// Fallback on error
		return "# Module Documentation\n\n" + moduleLinks.String()
	}
	return result
}
