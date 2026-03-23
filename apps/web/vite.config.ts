import { dirname, resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
const reactCompilerPlugin = "babel-plugin-react-compiler";
import alchemy from "alchemy/cloudflare/tanstack-start";
import { nitro } from "nitro/vite";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

// ALCHEMY=1 is set by root alchemy.run.ts for builds/deploys
const useAlchemy = process.env.ALCHEMY === "1";

// Docs proxy target - configure via DOCS_PROXY_URL env var
const docsProxyUrl = process.env.DOCS_PROXY_URL || "http://localhost:4000";

function readInstalledVersion(packageName: string) {
  try {
    const packageJsonPath = require.resolve(`${packageName}/package.json`);
    return require(packageJsonPath).version;
  } catch {
    return "unresolved";
  }
}

function deploymentDebugPlugin() {
  return {
    name: "stackpanel-deployment-debug",
    configResolved(resolvedConfig: import("vite").ResolvedConfig) {
      // #region agent log
      fetch("http://127.0.0.1:7788/ingest/cbd2d5d7-3242-45a9-9410-031ebd439ef5",{method:"POST",headers:{"Content-Type":"application/json","X-Debug-Session-Id":"4492a3"},body:JSON.stringify({sessionId:"4492a3",runId:"initial",hypothesisId:"H3",location:"apps/web/vite.config.ts:configResolved",message:"Resolved deploy build config",data:{command:resolvedConfig.command,mode:resolvedConfig.mode,useAlchemy,plugins:resolvedConfig.plugins.map((plugin)=>plugin.name),build:{ssr:resolvedConfig.build.ssr,minify:resolvedConfig.build.minify,sourcemap:resolvedConfig.build.sourcemap},versions:{streamdown:readInstalledVersion("streamdown"),shiki:readInstalledVersion("shiki"),baseUiReact:readInstalledVersion("@base-ui/react"),baseUiUtils:readInstalledVersion("@base-ui/utils")}},timestamp:Date.now()})}).catch(()=>{});
      // #endregion
    },
    buildStart() {
      // #region agent log
      fetch("http://127.0.0.1:7788/ingest/cbd2d5d7-3242-45a9-9410-031ebd439ef5",{method:"POST",headers:{"Content-Type":"application/json","X-Debug-Session-Id":"4492a3"},body:JSON.stringify({sessionId:"4492a3",runId:"initial",hypothesisId:"H4",location:"apps/web/vite.config.ts:buildStart",message:"Starting deploy bundle",data:{cwd:process.cwd(),nodeEnv:process.env.NODE_ENV ?? null,alchemy:process.env.ALCHEMY ?? null,docsProxyUrl},timestamp:Date.now()})}).catch(()=>{});
      // #endregion
    },
    buildEnd(error?: Error) {
      if (!error) {
        return;
      }
      // #region agent log
      fetch("http://127.0.0.1:7788/ingest/cbd2d5d7-3242-45a9-9410-031ebd439ef5",{method:"POST",headers:{"Content-Type":"application/json","X-Debug-Session-Id":"4492a3"},body:JSON.stringify({sessionId:"4492a3",runId:"initial",hypothesisId:"H4",location:"apps/web/vite.config.ts:buildEnd",message:"Deploy bundle failed",data:{name:error.name,message:error.message,stack:error.stack?.split("\n").slice(0,5)},timestamp:Date.now()})}).catch(()=>{});
      // #endregion
    },
    generateBundle(_options: unknown, bundle: Record<string, import("rollup").OutputAsset | import("rollup").OutputChunk>) {
      const interestingChunks = Object.values(bundle)
        .filter((item): item is import("rollup").OutputChunk => item.type === "chunk")
        .filter(
          (chunk) =>
            /shiki|streamdown|@base-ui|mermaid/i.test(chunk.fileName) ||
            Object.keys(chunk.modules).some((moduleId) =>
              /shiki|streamdown|@base-ui|mermaid/i.test(moduleId),
            ),
        )
        .map((chunk) => ({
          fileName: chunk.fileName,
          moduleCount: Object.keys(chunk.modules).length,
          renderedLength: chunk.code.length,
          sampleModules: Object.keys(chunk.modules).filter((moduleId) =>
            /shiki|streamdown|@base-ui|mermaid/i.test(moduleId),
          ).slice(0, 5),
        }));
      const largestChunks = Object.values(bundle)
        .filter((item): item is import("rollup").OutputChunk => item.type === "chunk")
        .map((chunk) => ({
          fileName: chunk.fileName,
          renderedLength: chunk.code.length,
          moduleCount: Object.keys(chunk.modules).length,
        }))
        .sort((left, right) => right.renderedLength - left.renderedLength)
        .slice(0, 10);
      // #region agent log
      fetch("http://127.0.0.1:7788/ingest/cbd2d5d7-3242-45a9-9410-031ebd439ef5",{method:"POST",headers:{"Content-Type":"application/json","X-Debug-Session-Id":"4492a3"},body:JSON.stringify({sessionId:"4492a3",runId:"initial",hypothesisId:"H1",location:"apps/web/vite.config.ts:generateBundle",message:"Generated deploy bundle summary",data:{interestingChunks,largestChunks},timestamp:Date.now()})}).catch(()=>{});
      // #endregion
    },
  } satisfies import("vite").Plugin;
}

export default defineConfig({
  plugins: [
    tsconfigPaths({
      projects: ["./tsconfig.json"],
    }),
    tailwindcss(),
    // Use alchemy for Cloudflare deployment, nitro for local dev (HMR)
    ...(useAlchemy ? [alchemy()] : [nitro()]),
    tanstackStart(),
    viteReact({
      babel: {
        plugins: [reactCompilerPlugin],
      },
    }),
    deploymentDebugPlugin(),
  ],
  resolve: {
    alias: {
      "@ui": resolve(__dirname, "src/components/ui"),
      "@gen/featureflags": resolve(
        __dirname,
        "../../packages/gen/featureflags/src",
      ),
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
