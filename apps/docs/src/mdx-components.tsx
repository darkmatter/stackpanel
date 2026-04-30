import defaultMdxComponents from "fumadocs-ui/mdx";
import type { MDXComponents } from "mdx/types";
import { Files, File, Folder } from "@/components/files";
import type { ReactNode } from "react";

// Note on `<AutoTypeTable>`: the MDX tag is *expanded at build time* by
// `remarkAutoTypeTable` in source.config.ts, so the rendered docs never
// contain a live `<AutoTypeTable>` element. Registering the runtime
// component here used to pull `fumadocs-typescript` → `ts-morph` into
// the Cloudflare Worker bundle, which (a) bloats it past the 64 MiB
// uncompressed Workers limit and (b) crashes at request time with
// `[unenv] fs.mkdir is not implemented yet!` from `ts-morph`'s
// `createFileSystemGeneratorCache`. Don't reintroduce a runtime
// `AutoTypeTable` registration unless you're prepared to (1) swap to a
// non-FS cache and (2) verify ts-morph still bundles cleanly under
// `nodejs_compat`.

// NixOption renders stale generated MDX files that still reference <NixOption>.
// It reconstructs the original markdown-table layout from the JSX props so the
// options reference pages look correct until docs are regenerated.
// Once `generate-docs` is re-run, the new files will use plain markdown and
// this component can be removed.
function NixOption({
  path,
  type,
  defaultValue,
  defaultCode,
  exampleCode,
  readonly,
  module,
  children,
}: {
  path?: string;
  type?: string;
  defaultValue?: string;
  defaultCode?: string;
  exampleCode?: string;
  readonly?: boolean;
  module?: string;
  children?: ReactNode;
}) {
  return (
    <div
      className={`my-6 ${readonly ? "border-l-4 border-amber-400 pl-4 dark:border-amber-600" : ""}`}
    >
      {path && (
        <h2 id={path} className="group flex items-center gap-2">
          <code>{path}</code>
          {readonly && (
            <span className="rounded-full border border-amber-300/70 bg-amber-100/80 px-2 py-0.5 text-xs font-medium text-amber-800 dark:border-amber-700/60 dark:bg-amber-900/30 dark:text-amber-300">
              read-only
            </span>
          )}
        </h2>
      )}

      {children && <div>{children}</div>}

      <table>
        <thead>
          <tr>
            <th>Property</th>
            <th>Value</th>
          </tr>
        </thead>
        <tbody>
          {type && (
            <tr>
              <td>
                <strong>Type</strong>
              </td>
              <td>
                <code>{type}</code>
              </td>
            </tr>
          )}
          {defaultValue !== undefined && (
            <tr>
              <td>
                <strong>Default</strong>
              </td>
              <td>
                <code>{defaultValue}</code>
              </td>
            </tr>
          )}
          {readonly && (
            <tr>
              <td>
                <strong>Read Only</strong>
              </td>
              <td>
                <code>true</code>
              </td>
            </tr>
          )}
          {module && (
            <tr>
              <td>
                <strong>Module</strong>
              </td>
              <td>
                <code>{module}</code>
              </td>
            </tr>
          )}
        </tbody>
      </table>

      {defaultCode && (
        <div className="mt-2">
          <p>
            <strong>Default:</strong>
          </p>
          <pre>
            <code>{defaultCode}</code>
          </pre>
        </div>
      )}

      {exampleCode && (
        <div className="mt-2">
          <p>
            <strong>Example:</strong>
          </p>
          <pre>
            <code>{exampleCode}</code>
          </pre>
        </div>
      )}

      <hr />
    </div>
  );
}

// Also register NixOptionMeta as a no-op in case any stale files reference it.
function NixOptionMeta() {
  return null;
}

export function getMDXComponents(components?: MDXComponents): MDXComponents {
  return {
    ...defaultMdxComponents,
    Files,
    File,
    Folder,
    NixOption,
    NixOptionMeta,
    ...components,
  };
}
