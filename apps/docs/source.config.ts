import {
  remarkAutoTypeTable,
  createGenerator,
  createFileSystemGeneratorCache,
} from "fumadocs-typescript";
import {
  defineConfig,
  defineDocs,
  frontmatterSchema,
  metaSchema,
} from "fumadocs-mdx/config";
import { type RehypeCodeOptions } from "fumadocs-core/mdx-plugins";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { remarkFiles } from "./src/lib/remark-files";

// Load custom theme using fs to avoid import issues with large JSON files
const customThemeJson = JSON.parse(
  readFileSync(join(process.cwd(), "src/lib/theme.json"), "utf-8"),
);

// Convert the VS Code theme to Shiki theme format
const customTheme = {
  name: customThemeJson.name,
  type: "dark" as const,
  colors: customThemeJson.colors,
  fg: customThemeJson.colors["editor.foreground"],
  bg: customThemeJson.colors["editor.background"],
  tokenColors: customThemeJson.tokenColors,
  settings: customThemeJson.tokenColors,
};

const rehypeCodeOptions: RehypeCodeOptions = {
  themes: {
    light: "github-light",
    dark: customTheme,
  },
};

const generator = createGenerator({
  // recommended: choose a directory for cache
  cache: createFileSystemGeneratorCache(".next/fumadocs-typescript"),
});

// You can customise Zod schemas for frontmatter and `meta.json` here
// see https://fumadocs.dev/docs/mdx/collections
export const docs = defineDocs({
  dir: "content/docs",
  docs: {
    schema: frontmatterSchema,
    postprocess: {
      includeProcessedMarkdown: true,
    },
  },
  meta: {
    schema: metaSchema,
  },
});

export default defineConfig({
  mdxOptions: {
    rehypeCodeOptions,
    remarkPlugins: [remarkFiles, [remarkAutoTypeTable, { generator }]],
  },
});
