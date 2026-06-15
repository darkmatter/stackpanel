import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
// import alchemy from "alchemy/cloudflare/tanstack-start";
import { execSync } from "node:child_process";
import type { Plugin } from "vite";
import { defineConfig } from "vite";

/**
 * Patches createRequire(import.meta.url) calls in the SSR bundle for
 * Cloudflare Workers, where import.meta.url is undefined.
 */
function patchImportMetaUrl(): Plugin {
  return {
    name: "patch-import-meta-url",
    applyToEnvironment(env) {
      return env.name === "ssr";
    },
    renderChunk(code) {
      if (code.includes("createRequire(import.meta.url)")) {
        return code.replace(
          /createRequire\(import\.meta\.url\)/g,
          'createRequire("file:///worker.mjs")',
        );
      }
      return null;
    },
  };
}

const docsProxyUrl = process.env.DOCS_PROXY_URL || "http://localhost:4000";

const commitSha = (() => {
  const fromCi = process.env.GITHUB_SHA;
  if (fromCi) return fromCi.slice(0, 7);
  try {
    return execSync("git rev-parse --short HEAD", { encoding: "utf8" }).trim();
  } catch {
    return "unknown";
  }
})();

export default defineConfig({
  define: {
    __COMMIT_SHA__: JSON.stringify(commitSha),
  },
  plugins: [
    tailwindcss(),
    tanstackStart(),
    viteReact(),
    patchImportMetaUrl(),
    // alchemy(),
  ],
  environments: {
    ssr: {
      // Cloudflare Workers builds only (ALCHEMY=1; set by the `build` script
      // and the deploy workflow). The SSR bundle then runs on workerd, where
      // the default (node) conditions resolve pg's optional `pg-cloudflare`
      // dependency to its empty stub (`dist/empty.js`) — every pg query then
      // dies at runtime with "CloudflareSocket is not a constructor" (500 on
      // every route). This mirrors @distilled.cloud/cloudflare-vite-plugin's
      // intended condition list, which TanStack Start otherwise overrides.
      // Container/EC2/Fly builds run the SSR bundle on bun/node, where the
      // default conditions are correct — don't touch them there.
      ...(process.env.ALCHEMY === "1"
        ? {
          resolve: {
            conditions: [
              "workerd",
              "worker",
              "module",
              "browser",
              "development|production",
            ],
          },
        }
        : {}),
      build: {
        rolldownOptions: {
          ...(process.env.ALCHEMY === "1"
            ? {
              // workerd-condition modules import `cloudflare:*` builtins.
              external: [/^cloudflare:/],
            }
            : {}),
          output: {
            inlineDynamicImports: true,
            ...(process.env.ALCHEMY === "1"
              ? {
                // CJS deps (pg & friends) are bundled with rolldown's
                // `__require` shim, which needs a module-scope `require`
                // for bare node builtins ("events", "util", …). workerd
                // has no global require — without this banner every pg
                // query throws `Calling \`require\` for "events" in an
                // environment that doesn't expose the \`require\` function`
                // (500 on every route).
                banner: [
                  'import { createRequire as __cfCreateRequire } from "node:module";',
                  'const require = __cfCreateRequire("file:///server.js");',
                ].join("\n"),
              }
              : {}),
          },
        },
      },
    },
  },
  server: {
    port: 3001,
    host: "0.0.0.0",
    allowedHosts: [
      "coopers-mac-studio",
      "coopers-mac-studio.local",
      "coopers-mac-studio.tail6277a6.ts.net",
    ],
    // Proxy /docs to docs server if configured
    proxy: docsProxyUrl
      ? {
        "/docs": {
          target: docsProxyUrl,
          changeOrigin: true,
        },
      }
      : undefined,
  },
});
