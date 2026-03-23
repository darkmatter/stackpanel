// ==============================================================================
// Deployment Infra Module
//
// Deploys app resources using app-scoped Alchemy apps so `alchemy deploy --app`
// follows Alchemy's documented monorepo workflow.
// ==============================================================================
import alchemy, { type Secret } from "alchemy";
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
import { Ec2Server } from "./aws-ec2-deploy";

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
const DEPLOYMENT_APP_FILTER = process.env.STACKPANEL_DEPLOYMENT_APP ?? null;

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

function resolveAwsEnvironment(
  bindingNames: string[],
  secretNames: string[],
): Record<string, string | Secret<string>> {
  const secretSet = new Set(secretNames);
  const resolved: Record<string, string | Secret<string>> = {};

  for (const key of bindingNames) {
    const envValue = process.env[key];
    const defaultFn = STAGE_URL_DEFAULTS[key];
    const value = envValue ?? (defaultFn ? defaultFn(STAGE) : "");
    if (secretSet.has(key)) {
      if (!value && STAGE === "prod") {
        throw new Error(`Missing required secret binding "${key}" for AWS deployment`);
      }
      resolved[key] = alchemy.secret(value || "PLACEHOLDER");
      continue;
    }
    resolved[key] = value;
  }

  return resolved;
}

function requireEnv(name: string) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} environment variable is required`);
  }
  return value;
}

function resolveArtifactLocation() {
  const artifactVersion = process.env.EC2_ARTIFACT_VERSION;
  const artifactBucket = process.env.EC2_ARTIFACT_BUCKET ?? inputs.aws?.artifact?.bucket;
  const artifactKey = process.env.EC2_ARTIFACT_KEY
    ?? (
      artifactVersion
        ? `${inputs.aws?.artifact?.keyPrefix ?? "web"}/${STAGE}/${artifactVersion}/release.tar.gz`
        : undefined
    );

  if (!artifactBucket) {
    throw new Error(
      "EC2_ARTIFACT_BUCKET is required unless stackpanel.deployment.aws.artifact.bucket is configured",
    );
  }

  if (!artifactKey) {
    throw new Error(
      "EC2_ARTIFACT_KEY is required unless EC2_ARTIFACT_VERSION and stackpanel.deployment.aws.artifact.keyPrefix are available",
    );
  }

  return {
    artifactBucket,
    artifactKey,
    artifactVersion,
  };
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

async function deployAwsApp(
  appName: string,
  app: AppInput,
): Promise<{ url: string }> {
  const environment = resolveAwsEnvironment(app.bindings, app.secrets);
  const plan = buildDeploymentPlan(appName, app);

  if (plan.kind !== "aws-ec2-app") {
    throw new Error(
      `Unsupported AWS deployment plan "${plan.kind}" for ${appName}`,
    );
  }

  const { artifactBucket, artifactKey, artifactVersion } = resolveArtifactLocation();
  const region = app.aws?.region ?? inputs.aws?.region ?? "us-west-2";

  const osType = (app.aws?.osType as "amazon-linux" | "nixos") ?? "amazon-linux";

  return withAppScope(plan.appScopeName, async () =>
    Ec2Server(plan.resourceName, {
      appName,
      artifactBucket,
      artifactKey,
      artifactVersion,
      environment,
      region,
      availabilityZone: app.aws?.availabilityZone ?? undefined,
      imageId: app.aws?.imageId ?? undefined,
      instanceType: app.aws?.instanceType ?? inputs.aws?.instanceType ?? undefined,
      keyName: app.aws?.keyName ?? undefined,
      parameterPath:
        app.aws?.parameterPath ?? `/stackpanel/${STAGE}/${appName}-runtime`,
      port: app.aws?.port ?? inputs.aws?.port ?? 80,
      httpCidrBlocks:
        app.aws?.httpCidrBlocks?.length ? app.aws.httpCidrBlocks : undefined,
      sshCidrBlocks:
        app.aws?.sshCidrBlocks?.length ? app.aws.sshCidrBlocks : undefined,
      rootVolumeSize: app.aws?.rootVolumeSize ?? undefined,
      vpcCidrBlock: app.aws?.vpcCidrBlock ?? undefined,
      subnetCidrBlock: app.aws?.subnetCidrBlock ?? undefined,
      osType,
      tags: {
        App: "stackpanel",
        Stage: STAGE,
        ...(app.aws?.tags ?? {}),
      },
    }),
  );
}

const outputs: Record<string, string> = {};
const deployableApps = Object.entries(inputs.apps ?? {}).filter(
  ([appName]) => DEPLOYMENT_APP_FILTER === null || appName === DEPLOYMENT_APP_FILTER,
);

for (const [appName, app] of deployableApps) {
  let resource: { url: string };

  switch (app.host) {
    case "cloudflare":
      resource = await deployCloudflareApp(appName, app);
      break;

    case "aws":
      resource = await deployAwsApp(appName, app);
      break;

    default:
      throw new Error(
        `Unsupported host "${app.host}" in infra deployment module`,
      );
  }

  outputs[`${appName}Url`] = resource.url;
  console.log(`[${STAGE}] ${appName} -> ${resource.url}`);
}

export default outputs;
