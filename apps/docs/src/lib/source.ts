import { docs } from "fumadocs-mdx:collections/server";
import { type InferPageType, loader } from "fumadocs-core/source";
import { icons } from "lucide-react";
import { rehypeCode, type RehypeCodeOptions } from "fumadocs-core/mdx-plugins";

import { createElement } from "react";

// Convert kebab-case or lowercase icon names to PascalCase for lucide-react
function toIconKey(name: string): keyof typeof icons | undefined {
  // Try exact match first
  if (name in icons) return name as keyof typeof icons;

  // Convert kebab-case or lowercase to PascalCase
  const pascalCase = name
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");

  if (pascalCase in icons) return pascalCase as keyof typeof icons;

  return undefined;
}

// See https://fumadocs.dev/docs/headless/source-api for more info
export const source = loader({
  baseUrl: "/docs",
  source: docs.toFumadocsSource(),
  icon(icon) {
    if (!icon || typeof icon !== "string") return;

    const iconKey = toIconKey(icon);
    if (iconKey) {
      return createElement(icons[iconKey], {
        className: "size-4 shrink-0",
      });
    }
  },
});

export function getPageImage(page: InferPageType<typeof source>) {
  const segments = [...page.slugs, "image.png"];

  return {
    segments,
    url: `/og/docs/${segments.join("/")}`,
  };
}

export async function getLLMText(page: InferPageType<typeof source>) {
  const processed = await page.data.getText("processed");

  return `# ${page.data.title}

${processed}`;
}
