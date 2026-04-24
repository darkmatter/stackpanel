// Shared helpers for `apps/*/alchemy.run.ts` deploy entrypoints.
//
// Centralises three pieces of logic that previously diverged across apps:
//   - Mapping `--stage` / `STAGE` onto the SOPS env namespace name we use on
//     disk (`prod`, `staging`, `dev`).
//   - Loading the per-app encrypted env payload via `@gen/env` and validating
//     that every variable declared `required = true` in `apps.<app>.env` is
//     actually present (so the deploy fails *before* any provider call with a
//     copy-pasteable error message instead of an opaque `Unauthorized`).
//   - Producing a consistent `https://...` URL for `console.log`-ing the
//     deployment result.

import { loaders } from "@gen/env";
import { EnvValidationError } from "@gen/env/runtime";

export type DeployAppEnv = "dev" | "staging" | "prod";

export interface ResolvedStage {
  /** Raw stage as alchemy will see it (e.g. `production`, `staging`, `dev`, `pr-42`). */
  readonly stage: string;
  /** SOPS env namespace this stage maps to (`prod` | `staging` | `dev`). */
  readonly appEnv: DeployAppEnv;
}

/**
 * Resolve the deploy stage from `process.env`.
 *
 * Source priority:
 *   1. `APP_ENV`         — explicit override, takes precedence over everything.
 *   2. `STAGE`           — set by `just deploy-alchemy` and CI.
 *   3. `ALCHEMY_STAGE`   — alchemy's own env var.
 *   4. argv `--stage X`  — the flag alchemy itself parses; cheap to read here
 *                          so single-shot `bun alchemy.run.ts --stage staging`
 *                          works without wrapping in `STAGE=...`.
 *   5. fallback `dev`.
 *
 * The returned `appEnv` is the SOPS namespace (`prod`/`staging`/`dev`). Anything
 * that isn't `production` or `staging` (e.g. `dev`, `pr-42`, branch names) maps
 * to `dev` so preview deploys reuse the dev secrets — same behaviour as the
 * previous per-app inline logic.
 */
export function resolveDeployStage(): ResolvedStage {
  const fromArgv = readStageFromArgv(process.argv);
  const stage =
    process.env.APP_ENV ||
    process.env.STAGE ||
    process.env.ALCHEMY_STAGE ||
    fromArgv ||
    "dev";

  const appEnv: DeployAppEnv =
    stage === "production" || stage === "prod"
      ? "prod"
      : stage === "staging"
        ? "staging"
        : "dev";

  return { stage, appEnv };
}

/**
 * Apps known to the typed loader registry — i.e. anything that exposes a
 * `loaders.<app>.<env>()` accessor in `@gen/env`. Excludes the bare scope
 * accessors (`loaders.deploy`) which are loaded separately.
 */
type AppLoaders = {
  [K in keyof typeof loaders as (typeof loaders)[K] extends (
    options?: unknown,
  ) => Promise<unknown>
    ? never
    : K]: (typeof loaders)[K];
};
export type DeployApp = keyof AppLoaders;

/**
 * Decrypt the per-app SOPS payload AND the cross-cutting `deploy` env scope,
 * inject them into `process.env` for downstream provider SDKs, and validate
 * every `required = true` variable is set in both.
 *
 * Two payloads are loaded:
 *   - `loaders.<app>.<appEnv>()`  — runtime env for the app being deployed
 *     (DATABASE_URL, BETTER_AUTH_SECRET, …).
 *   - `loaders.deploy()`          — cross-cutting deploy-time secrets
 *     contributed by the deploy module (CLOUDFLARE_API_TOKEN, NEON_API_KEY,
 *     ALCHEMY_STATE_TOKEN, …) — exists so these credentials don't need to be
 *     copied into every app's `apps.<app>.env`.
 *
 * The merged env is returned as a single record (`deploy` scope wins on
 * conflict, matching the env injection order). Throws `EnvValidationError`
 * (re-wrapped as `Error` so alchemy/Effect doesn't swallow the message)
 * with a multi-line, copy-pasteable list of every missing variable.
 *
 * `app` is constrained to the known typed app loaders so callers get IDE
 * autocomplete (`loaders.web` / `loaders.docs` / …) instead of having to
 * remember the literal app name. `appEnv` is constrained per-app to the
 * environments declared in `apps.<app>.environmentIds`.
 */
export async function loadDeployEnv<App extends DeployApp>(
  app: App,
  appEnv: keyof AppLoaders[App] & string,
): Promise<Record<string, string>> {
  try {
    const appLoader = (loaders as AppLoaders)[app][
      appEnv as keyof AppLoaders[App]
    ] as (options?: { inject?: boolean; validate?: boolean }) => Promise<
      Record<string, string>
    >;
    const appPayload = await appLoader({ inject: true, validate: true });
    // Load the `deploy` scope after the app payload so deploy-time secrets
    // (which are project-wide and never overridden per-app) take precedence
    // if the same key is somehow declared in both places.
    const deployPayload = await loaders.deploy({
      inject: true,
      validate: true,
    });
    return { ...appPayload, ...deployPayload };
  } catch (err) {
    if (err instanceof EnvValidationError) {
      throw new Error(err.message);
    }
    throw err;
  }
}

/**
 * Reads `--stage X` or `--stage=X` from a process argv array. Returns the
 * value, or `null` if not present.
 */
function readStageFromArgv(argv: ReadonlyArray<string>): string | null {
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--stage" && i + 1 < argv.length) {
      const next = argv[i + 1];
      if (next && !next.startsWith("--")) return next;
    }
    if (arg && arg.startsWith("--stage=")) {
      return arg.slice("--stage=".length);
    }
  }
  return null;
}
