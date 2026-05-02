import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
// import alchemy from "alchemy/cloudflare/tanstack-start";
import { execSync } from "node:child_process";
import type { Plugin } from "vite";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

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
    tsconfigPaths({
      skip: (dir) => dir === ".worktrees" || dir === ".stack",
    }),
    tailwindcss(),
    tanstackStart(),
    viteReact(),
    patchImportMetaUrl(),
    // alchemy(),
  ],
  environments: {
    ssr: {
      build: {
        rolldownOptions: {
          output: {
            inlineDynamicImports: true,
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
