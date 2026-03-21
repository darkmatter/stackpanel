// ==============================================================================
// Deployment Infra Module
//
// Deploys app resources using app-scoped Alchemy apps so `alchemy deploy --app`
// follows Alchemy's documented monorepo workflow.
// ==============================================================================
import alchemy from "alchemy";
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { TanStackStart } from "alchemy/cloudflare";
import * as cloudflare from "alchemy/cloudflare";
import { CloudflareStateStore } from "alchemy/state";
import Infra from "@stackpanel/infra";
import {
  buildDeploymentPlan,
  type AppInput,
  type DeploymentInputs,
} from "./plan";

type CreateApp = (name?: string) => Promise<{ finalize(): Promise<void> }>;

let createApp: CreateApp;
try {
  const mod = await import("@gen/alchemy");
  createApp = mod.createApp;
} catch {
  createApp = async (name?: string) =>
    alchemy(name ?? "stackpanel-infra", {
      stage: process.env.STAGE ?? undefined,
      stateStore: process.env.CLOUDFLARE_API_TOKEN
        ? (scope) =>
            new CloudflareStateStore(scope, {
              apiToken: alchemy.secret(process.env.CLOUDFLARE_API_TOKEN!),
            })
        : undefined,
    });
}

const infra = new Infra("deployment");
const inputs = infra.inputs<DeploymentInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const STAGE = process.env.STAGE ?? "dev";

const STAGE_URL_DEFAULTS: Record<string, (stage: string) => string> = {
  CORS_ORIGIN: (stage) =>
    stage === "prod"
      ? "https://stackpanel.com"
      : `https://${stage}.stackpanel.com`,
  BETTER_AUTH_URL: (stage) =>
    stage === "prod"
      ? "https://stackpanel.com"
      : `https://${stage}.stackpanel.com`,
  POLAR_SUCCESS_URL: (stage) =>
    stage === "prod"
      ? "https://stackpanel.com"
      : `https://${stage}.stackpanel.com`,
};

function resolveBindings(
  bindingNames: string[],
  secretNames: string[],
): Record<string, unknown> {
  const secretSet = new Set(secretNames);
  const resolved: Record<string, unknown> = {};

  for (const key of bindingNames) {
    const envValue = process.env[key];
    const defaultFn = STAGE_URL_DEFAULTS[key];
    const value = envValue ?? (defaultFn ? defaultFn(STAGE) : undefined);
    resolved[key] = secretSet.has(key) ? alchemy.secret(value ?? "") : value;
  }

  return resolved;
}

function cloudflareProps(name: string, app: AppInput) {
  const route = app.cloudflare?.route ?? inputs.cloudflare?.defaultRoute ?? null;

  return {
    adopt: true,
    cwd: app.path,
    name: app.cloudflare?.workerName ?? name,
    url: true,
    compatibility: app.cloudflare?.compatibility,
    compatibilityDate: inputs.cloudflare?.compatibilityDate ?? undefined,
    routes: route ? [route] : undefined,
  };
}

const OPENNEXT_RUNTIME_PATCH = [
  'const runtimeProcess = globalThis.process ?? process ?? {};',
  'globalThis.process = runtimeProcess;',
  'runtimeProcess.version ??= "v22.14.0";',
  'runtimeProcess.versions ??= {};',
  'Object.assign(runtimeProcess.versions, { node: "22.14.0", ...runtimeProcess.versions });',
].join("\n");

const OPENNEXT_RUNTIME_REGEX =
  /(\s*)Object\.assign\(process, \{ version: process\.version \|\| "v22\.14\.0" \}\);\n\1Object\.assign\(process\.versions, \{ node: "22\.14\.0", \.\.\.process\.versions \}\);/;

const OPENNEXT_DEBUG_FETCH_FROM = `async fetch(request, env, ctx) {
        return runWithCloudflareRequestContext(request, env, ctx, async () => {`;

const OPENNEXT_DEBUG_FETCH_TO = `async fetch(request, env, ctx) {
        try {
            return runWithCloudflareRequestContext(request, env, ctx, async () => {`;

const OPENNEXT_DEBUG_FETCH_END_FROM = `        });
    },`;

const OPENNEXT_DEBUG_FETCH_END_TO = `        });
        } catch (error) {
            if (request.headers.get("x-stackpanel-debug") === "1") {
                const stack = error instanceof Error ? \`${"${error.message}"}\n${"${error.stack ?? \"\"}"}\` : String(error);
                return new Response(stack, {
                    status: 500,
                    headers: { "content-type": "text/plain; charset=UTF-8" }
                });
            }
            throw error;
        }
    },`;

function buildNextjsWorker(app: AppInput) {
  const appPath = path.resolve(app.path);

  execFileSync("bunx", ["opennextjs-cloudflare", "build"], {
    cwd: appPath,
    stdio: "inherit",
  });

  const initPath = path.join(appPath, ".open-next", "cloudflare", "init.js");
  const initSource = readFileSync(initPath, "utf8");

  if (!initSource.includes(OPENNEXT_RUNTIME_PATCH) && !OPENNEXT_RUNTIME_REGEX.test(initSource)) {
    throw new Error(
      `OpenNext runtime patch target not found in ${initPath}`,
    );
  }

  if (!initSource.includes(OPENNEXT_RUNTIME_PATCH)) {
    writeFileSync(
      initPath,
      initSource.replace(
        OPENNEXT_RUNTIME_REGEX,
        (_match, indent: string) =>
          OPENNEXT_RUNTIME_PATCH.split("\n")
            .map((line) => `${indent}${line}`)
            .join("\n"),
      ),
    );
  }

  const pending = [path.join(appPath, ".open-next")];
  while (pending.length > 0) {
    const currentPath = pending.pop()!;
    for (const entry of readdirSync(currentPath, { withFileTypes: true })) {
      const entryPath = path.join(currentPath, entry.name);

      if (entry.isDirectory()) {
        pending.push(entryPath);
        continue;
      }

      if (!entry.isFile() || (!entry.name.endsWith(".js") && !entry.name.endsWith(".mjs"))) {
        continue;
      }

      const source = readFileSync(entryPath, "utf8");
      if (source.includes("Object.entries(env)")) {
        writeFileSync(
          entryPath,
          source.replaceAll(
            "Object.entries(env)",
            "Object.entries(env ?? {})",
          ),
        );
      }
    }
  }

  if (process.env.STACKPANEL_DEPLOYMENT_DEBUG_RESPONSE === "1") {
    const workerPath = path.join(appPath, ".open-next", "worker.js");
    const workerSource = readFileSync(workerPath, "utf8");

    if (
      workerSource.includes(OPENNEXT_DEBUG_FETCH_FROM) &&
      workerSource.includes(OPENNEXT_DEBUG_FETCH_END_FROM)
    ) {
      writeFileSync(
        workerPath,
        workerSource
          .replace(OPENNEXT_DEBUG_FETCH_FROM, OPENNEXT_DEBUG_FETCH_TO)
          .replace(OPENNEXT_DEBUG_FETCH_END_FROM, OPENNEXT_DEBUG_FETCH_END_TO),
      );
    }
  }
}

async function withAppScope<T>(
  appScopeName: string,
  run: () => Promise<T>,
): Promise<T> {
  const app = await createApp(appScopeName);

  try {
    const result = await run();
    await app.finalize();
    return result;
  } catch (error) {
    await app.finalize();
    throw error;
  }
}

async function deployCloudflareApp(
  appName: string,
  app: AppInput,
): Promise<{ url: string }> {
  const bindings = resolveBindings(app.bindings, app.secrets);
  const plan = buildDeploymentPlan(appName, app);

  return withAppScope(plan.appScopeName, async () => {
    switch (plan.kind) {
      case "cloudflare-nextjs-app":
        buildNextjsWorker(app);

        return cloudflare.Worker(plan.resourceName, {
          ...cloudflareProps(appName, app),
          assets: {
            html_handling: "auto-trailing-slash",
            not_found_handling: "none",
            run_worker_first: false,
          },
          bindings: {
            ...bindings,
            ASSETS: {
              path: path.join(app.path, ".open-next", "assets"),
              type: "assets",
            },
          },
          entrypoint: ".open-next/worker.js",
          noBundle: true,
          rules: [
            {
              globs: [
                "**/*.js",
                "**/*.mjs",
                "**/*.wasm",
                ".build/**/*.js",
                ".build/**/*.mjs",
              ],
            },
          ],
        });

      case "cloudflare-app":
        switch (plan.framework) {
          case "tanstack-start":
            return TanStackStart(plan.resourceName, {
              ...cloudflareProps(appName, app),
              bindings,
            });

          case "astro":
            return (await import("alchemy/cloudflare")).Astro(plan.resourceName, {
              ...cloudflareProps(appName, app),
              bindings,
            });

          case "remix":
            return (await import("alchemy/cloudflare")).Remix(plan.resourceName, {
              ...cloudflareProps(appName, app),
              bindings,
            });

          case "nuxt":
            return (await import("alchemy/cloudflare")).Nuxt(plan.resourceName, {
              ...cloudflareProps(appName, app),
              bindings,
            });

          case "vite":
            return cloudflare.Vite(plan.resourceName, {
              ...cloudflareProps(appName, app),
              assets: app.assetsDir ?? "dist",
              bindings,
              dev: { command: "bun run dev" },
            });

          case "hono":
            return cloudflare.Worker(plan.resourceName, {
              ...cloudflareProps(appName, app),
              entrypoint: app.entrypoint ?? "src/index.ts",
              bindings,
            });

          default:
            throw new Error(
              `Unsupported framework "${plan.framework}" for host "cloudflare"`,
            );
        }
    }
  });
}

const outputs: Record<string, string> = {};

for (const [appName, app] of Object.entries(inputs.apps)) {
  if (app.host !== "cloudflare") {
    throw new Error(
      `Unsupported host "${app.host}" in infra deployment module (expected: cloudflare)`,
    );
  }

  const resource = await deployCloudflareApp(appName, app);
  outputs[`${appName}Url`] = resource.url;
  console.log(`[${STAGE}] ${appName} -> ${resource.url}`);
}

export default outputs;
