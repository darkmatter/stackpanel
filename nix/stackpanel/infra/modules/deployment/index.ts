// ==============================================================================
// Deployment Infra Module
//
// Creates alchemy resources for each deployable app based on framework × host.
//
// Inputs (from Nix via infra-inputs.json):
//   apps: Record<string, {
//     framework: "tanstack-start" | "nextjs" | "vite" | "hono" | "astro" | "remix" | "nuxt"
//     host: "cloudflare" | "fly" | "vercel" | "aws"
//     path: string
//     bindings: string[]
//     secrets: string[]
//   }>
//
// Outputs:
//   { [appName + "Url"]: string }
// ==============================================================================
import alchemy from "alchemy";
import { TanStackStart } from "alchemy/cloudflare";
import * as cloudflare from "alchemy/cloudflare";
import Infra from "@stackpanel/infra";

interface AppInput {
  framework: string;
  host: string;
  path: string;
  bindings: string[];
  secrets: string[];
  // Framework-specific (optional)
  ssr?: boolean;
  assetsDir?: string;
  entrypoint?: string;
  output?: string;
}

interface DeploymentInputs {
  apps: Record<string, AppInput>;
}

const infra = new Infra("deployment");
const inputs = infra.inputs<DeploymentInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

// ---------------------------------------------------------------------------
// Resolve bindings from process.env, wrapping secrets with alchemy.secret()
// ---------------------------------------------------------------------------
function resolveBindings(
  bindingNames: string[],
  secretNames: string[],
): Record<string, unknown> {
  const secretSet = new Set(secretNames);
  const resolved: Record<string, unknown> = {};

  for (const key of bindingNames) {
    const value = process.env[key];
    resolved[key] = secretSet.has(key) ? alchemy.secret(value ?? "") : value;
  }

  return resolved;
}

// ---------------------------------------------------------------------------
// Create the appropriate alchemy resource for a framework × host pair
// ---------------------------------------------------------------------------
async function deployApp(
  name: string,
  app: AppInput,
): Promise<{ url: string }> {
  const bindings = resolveBindings(app.bindings, app.secrets);

  if (app.host === "cloudflare") {
    switch (app.framework) {
      case "tanstack-start":
        return TanStackStart(name, {
          adopt: true,
          cwd: app.path,
          bindings,
        });

      case "nextjs":
        // @ts-expect-error — Nextjs may not be available in all alchemy versions
        return (await import("alchemy/cloudflare")).Nextjs(name, {
          adopt: true,
          cwd: app.path,
          bindings,
        });

      case "astro":
        // @ts-expect-error — Astro may not be available in all alchemy versions
        return (await import("alchemy/cloudflare")).Astro(name, {
          adopt: true,
          cwd: app.path,
          bindings,
        });

      case "remix":
        // @ts-expect-error — Remix may not be available in all alchemy versions
        return (await import("alchemy/cloudflare")).Remix(name, {
          adopt: true,
          cwd: app.path,
          bindings,
        });

      case "nuxt":
        // @ts-expect-error — Nuxt may not be available in all alchemy versions
        return (await import("alchemy/cloudflare")).Nuxt(name, {
          adopt: true,
          cwd: app.path,
          bindings,
        });

      case "vite":
        return cloudflare.Vite(name, {
          adopt: true,
          cwd: app.path,
          assets: app.assetsDir ?? "dist",
          bindings,
          dev: { command: "bun run dev" },
        });

      case "hono":
        return cloudflare.Worker(name, {
          adopt: true,
          cwd: app.path,
          entrypoint: app.entrypoint ?? "src/index.ts",
          compatibility: "node",
          bindings,
        });

      default:
        throw new Error(
          `Unsupported framework "${app.framework}" for host "cloudflare"`,
        );
    }
  }

  // Future: fly, vercel, aws
  throw new Error(`Unsupported host "${app.host}"`);
}

// ---------------------------------------------------------------------------
// Deploy all apps and collect outputs
// ---------------------------------------------------------------------------
const outputs: Record<string, string> = {};

for (const [appName, app] of Object.entries(inputs.apps)) {
  const resource = await deployApp(appName, app);
  outputs[`${appName}Url`] = resource.url;
  console.log(`${appName} -> ${resource.url}`);
}

export default outputs;
