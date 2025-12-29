import defaultMdxComponents from "fumadocs-ui/mdx";
import type { MDXComponents } from "mdx/types";
import { createGenerator, createFileSystemGeneratorCache } from "fumadocs-typescript";
import { AutoTypeTable } from "fumadocs-typescript/ui";
import { Files, File, Folder } from "@/components/files";

const generator = createGenerator({
  // recommended: choose a directory for cache
  cache: createFileSystemGeneratorCache(".next/fumadocs-typescript"),
});

export function getMDXComponents(components?: MDXComponents): MDXComponents {
  return {
    ...defaultMdxComponents,
    AutoTypeTable: (props) => <AutoTypeTable {...props} generator={generator} />,
    Files,
    File,
    Folder,
    ...components,
  };
}
