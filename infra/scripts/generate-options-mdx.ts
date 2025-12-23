#!/usr/bin/env bun
/**
 * Generate MDX documentation from Nix options JSON
 *
 * Usage: bun run generate-options-mdx.ts <options.json> <output-dir>
 */

import { mkdirSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";

interface NixOption {
	declarations: Array<{ name: string; url: string | null }>;
	default?: { text: string; _type?: string } | null;
	description?: string;
	example?: { text: string; _type?: string } | null;
	loc: string[];
	readOnly?: boolean;
	type: string;
}

type OptionsJson = Record<string, NixOption>;

// Group options by their top-level category
function groupOptions(options: OptionsJson): Record<string, OptionsJson> {
	const groups: Record<string, OptionsJson> = {};

	for (const [path, opt] of Object.entries(options)) {
		// Remove 'stackpanel.' prefix and get first segment
		const withoutPrefix = path.replace(/^stackpanel\./, "");
		const parts = withoutPrefix.split(".");
		const category = parts[0] || "core";

		if (!groups[category]) {
			groups[category] = {};
		}
		groups[category][path] = opt;
	}

	return groups;
}

// Format a Nix value for display in a table cell (inline only)
function formatValueInline(
	val: { text: string; _type?: string } | null | undefined,
): string {
	if (!val) return "_none_";
	const text = val.text.trim();
	// For simple single-line values, use inline code
	if (!text.includes("\n") && text.length < 60) {
		return `\`${text}\``;
	}
	// For multi-line or long values, indicate there's a default and show it separately
	return "_see below_";
}

// Format a Nix value as a code block (for display outside tables)
function formatValueBlock(
	val: { text: string; _type?: string } | null | undefined,
): string | null {
	if (!val) return null;
	const text = val.text.trim();
	// Only return a block if it's multi-line or long
	if (text.includes("\n") || text.length >= 60) {
		return `\`\`\`nix\n${text}\n\`\`\``;
	}
	return null;
}

// Convert option description (may contain markdown)
function formatDescription(desc: string | undefined): string {
	if (!desc) return "_No description provided._";
	// Clean up any docbook/xml remnants
	return desc
		.replace(/<[^>]+>/g, "")
		.replace(/\{@link ([^}]+)\}/g, "`$1`")
		.trim();
}

// Generate MDX for a single category
function generateCategoryMdx(category: string, options: OptionsJson): string {
	const title = category.charAt(0).toUpperCase() + category.slice(1);
	const sortedOptions = Object.entries(options).sort(([a], [b]) =>
		a.localeCompare(b),
	);

	let mdx = `---
title: ${title} Options
description: Configuration options for stackpanel.${category}
---

# ${title} Options

`;

	for (const [path, opt] of sortedOptions) {
		const anchor = path.replace(/\./g, "-").replace(/[<>]/g, "");
		const defaultBlock = formatValueBlock(opt.default);
		const exampleBlock = formatValueBlock(opt.example);

		mdx += `## \`${path}\`

${formatDescription(opt.description)}

| Property | Value |
|----------|-------|
| **Type** | \`${opt.type}\` |
| **Default** | ${formatValueInline(opt.default)} |
${opt.readOnly ? "| **Read Only** | `true` |\n" : ""}
`;

		// Show default as a code block if it's multi-line
		if (defaultBlock) {
			mdx += `
**Default:**

${defaultBlock}

`;
		}

		if (opt.example) {
			mdx += `
**Example:**

${exampleBlock || `\`${opt.example.text}\``}

`;
		}

		mdx += "\n---\n\n";
	}

	return mdx;
}

// Generate index page
function generateIndexMdx(categories: string[]): string {
	const categoryLinks = categories
		.sort()
		.map(
			(cat) => `  - [${cat.charAt(0).toUpperCase() + cat.slice(1)}](./${cat})`,
		)
		.join("\n");

	return `---
title: Options Reference
description: Complete reference for all stackpanel configuration options
---

# Options Reference

This section documents all available configuration options for stackpanel.

## Categories

${categoryLinks}

## Quick Start

\`\`\`nix
# In your devenv.nix
{
  stackpanel = {
    enable = true;

    # Port management
    ports.projectName = "myproject";

    # Services
    globalServices.postgres.enable = true;
    globalServices.redis.enable = true;

    # Theme
    theme.enable = true;
  };
}
\`\`\`
`;
}

// Main
function main() {
	const args = process.argv.slice(2);

	if (args.length < 2) {
		console.error("Usage: generate-options-mdx.ts <options.json> <output-dir>");
		process.exit(1);
	}

	const [optionsPath, outputDir] = args;

	console.log(`Reading options from: ${optionsPath}`);
	const optionsJson: OptionsJson = JSON.parse(
		readFileSync(optionsPath, "utf-8"),
	);

	console.log(`Found ${Object.keys(optionsJson).length} options`);

	// Group by category
	const groups = groupOptions(optionsJson);
	const categories = Object.keys(groups);

	console.log(`Categories: ${categories.join(", ")}`);

	// Ensure output directory exists
	mkdirSync(outputDir, { recursive: true });

	// Generate index
	const indexPath = join(outputDir, "index.mdx");
	writeFileSync(indexPath, generateIndexMdx(categories));
	console.log(`  ✓ ${indexPath}`);

	// Generate category pages
	for (const [category, options] of Object.entries(groups)) {
		const categoryPath = join(outputDir, `${category}.mdx`);
		writeFileSync(categoryPath, generateCategoryMdx(category, options));
		console.log(`  ✓ ${categoryPath} (${Object.keys(options).length} options)`);
	}

	console.log(`\nGenerated ${categories.length + 1} files`);
}

main();
