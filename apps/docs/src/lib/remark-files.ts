import { remarkMdxFiles } from "fumadocs-core/mdx-plugins";
import { visit } from "unist-util-visit";
import type { Root, Code } from "mdast";
import type { MdxJsxFlowElement, MdxJsxAttribute } from "mdast-util-mdx-jsx";

const HIGHLIGHT_MARKER = /\s*\/\/\s*\[!code highlight\]/;

export interface RemarkFilesOptions {
  /**
   * Language identifier for the code block
   * @default "files"
   */
  lang?: string;
}

/**
 * Wraps fumadocs remarkMdxFiles plugin to add highlight support.
 * Use `// [!code highlight]` at the end of a line to highlight that file/folder.
 */
export function remarkFiles(options: RemarkFilesOptions = {}) {
  const { lang = "files" } = options;

  return (tree: Root) => {
    // First pass: collect highlight info and strip markers from code
    const highlightedNames = new Set<string>();

    visit(tree, "code", (node: Code) => {
      if (node.lang !== lang || !node.value) return;

      const cleanedLines: string[] = [];

      for (const line of node.value.split(/\r?\n/)) {
        if (HIGHLIGHT_MARKER.test(line)) {
          // Extract the filename from the line
          const cleanLine = line.replace(HIGHLIGHT_MARKER, "");
          cleanedLines.push(cleanLine);

          // Parse out the actual name (strip tree chars)
          let name = cleanLine;
          let match: RegExpExecArray | null;
          while ((match = /(?:├──|│|└──)\s*/.exec(name))) {
            name = name.slice(match[0].length);
          }
          if (name) {
            highlightedNames.add(name.replace(/\/$/, "")); // Remove trailing slash for folders
          }
        } else {
          cleanedLines.push(line);
        }
      }

      // Update the code block with cleaned content (markers stripped)
      node.value = cleanedLines.join("\n");
    });

    // Run the original plugin's transformer to convert code blocks to JSX
    const transformer = remarkMdxFiles({ lang });
    (transformer as (tree: Root) => void)(tree);

    // Second pass: add highlighted attribute to matching File/Folder elements
    if (highlightedNames.size > 0) {
      visit(tree, "mdxJsxFlowElement", (node: MdxJsxFlowElement) => {
        if (node.name !== "File" && node.name !== "Folder") return;

        // Find the name attribute
        const nameAttr = node.attributes.find(
          (attr): attr is MdxJsxAttribute =>
            attr.type === "mdxJsxAttribute" && attr.name === "name",
        );

        if (!nameAttr || typeof nameAttr.value !== "string") return;

        const fileName = nameAttr.value.replace(/\/$/, "");

        if (highlightedNames.has(fileName)) {
          node.attributes.push({
            type: "mdxJsxAttribute",
            name: "highlighted",
            value: null,
          });
        }
      });
    }
  };
}
