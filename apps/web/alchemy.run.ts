import {
  loadDeployEnv,
  resolveDeployStage,
  selectStateBackend,
} from "@stackpanel/infra/lib/deploy";
import { NeonProject, neonProviders } from "@stackpanel/infra/resources/neon";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Output from "alchemy/Output";
import * as Workers from "@distilled.cloud/cloudflare/workers";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

const PROJECT = "stackpanel";
const SERVICE = "web";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); `stage` is what
// alchemy itself sees and mirrors into `Stage`. Both are derived from a single
// source of truth so the secrets we decrypt match the resources we provision.
const { appEnv } = resolveDeployStage();

// Decrypts the per-app SOPS payload (CLOUDFLARE_*, NEON_API_KEY, …) and injects
// it into process.env so downstream Cloudflare/Neon providers see it. Hard-fails
// with a copy-pasteable message listing every missing required env var.
await loadDeployEnv(SERVICE, appEnv);

// stackpanel.com
const STACKPANEL_ZONE = "d34628a3ab639230ff1f6dc1eb640eec";

const program = Effect.gen(function* () {
  const stage = yield* Alchemy.Stage;

  const db = yield* NeonProject("postgres", {
    name: `${PROJECT}-${stage}`,
    regionId: "aws-us-east-1",
    pgVersion: 17,
    databaseName: `${SERVICE}_${stage}`,
    roleName: `${PROJECT}-${SERVICE}-owner`,
  });

  // The Worker decrypts its own runtime secrets at boot via
  // `await loadAppEnv("web", APP_ENV, { inject: true })` in
  // `apps/web/src/server.ts`, against the per-stage SOPS payload
  // embedded in `@gen/env`. We forward only the two non-secret-payload
  // values the loader needs:
  //
  //   - `SOPS_AGE_KEY`: the AGE key material that unlocks every entry in
  //     the embedded SOPS payload. Lives in the deploy scope (CI gets it
  //     from `secrets.SECRETS_AGE_KEY_DEV`; dev gets it from
  //     `.stack/keys/local.txt` via `loadDeployEnv` above) and is read
  //     here from `process.env`.
  //   - `APP_ENV`: the resolved SOPS namespace (`prod` | `staging` |
  //     `dev`) so the Worker knows which `web/<env>.ts` payload to load.
  //   - `DATABASE_URL`: a runtime-bound resource output from the Neon
  //     project. Not a SOPS secret; it doesn't belong in `@gen/env`
  //     because the connection URI is generated per-deploy by alchemy.
  //
  // Adding a new app secret only requires editing
  // `.stack/config.apps.nix:envs.shared` (and re-running `stackpanel
  // codegen build`); it lands in the embedded payload automatically and
  // becomes available to the Worker via `process.env` after the
  // `loadAppEnv` call. See
  // `docs/adr/0001-runtime-secrets-via-gen-env-loader.md`.
  const website = yield* Cloudflare.Vite("TanstackStart", {
    compatibility: {
      flags: ["nodejs_compat"],
    },
    env: {
      DATABASE_URL: db.connectionUri,
      SOPS_AGE_KEY: process.env.SOPS_AGE_KEY ?? "",
      APP_ENV: appEnv,
    },
  });
  let url: Output.Output<string | undefined> = website.url;

  if (stage !== "dev") {
    // Production binds two hostnames to the same worker:
    //   - apex stackpanel.com → marketing/landing (`/`, `/login`, …)
    //   - local.stackpanel.com → studio (mirrors local.drizzle.studio: the
    //     `/studio/*` routes talk to the user's machine via
    //     http://127.0.0.1:9876).
    // Both ship the same bundle today; auth cookies are scoped to
    // `.stackpanel.com` so a session from the apex carries into the studio.
    // Non-prod stages only get the studio hostname — there's no marketing
    // preview to host on the apex.
    const hostnames =
      stage === "production"
        ? ["local.stackpanel.com", "stackpanel.com"]
        : [`local.${stage}.stackpanel.com`];
    const primary = hostnames[0]!;
    url = Output.all(website.accountId, website.workerName).pipe(
      Output.mapEffect(([accountId, workerName]) =>
        Effect.gen(function* () {
          for (const hostname of hostnames) {
            const existing = yield* Workers.listDomains({
              accountId,
              hostname,
            });
            const stale = existing.result.filter(
              (d) => d.hostname === hostname && d.id,
            );
            if (stale.length > 0) {
              yield* Effect.log(
                `[alchemy] purging ${stale.length} existing binding(s) at ${hostname}: ${stale
                  .map((d) => `${d.service ?? "?"}#${d.id}`)
                  .join(", ")}`,
              );
            }
            for (const d of stale) {
              yield* Workers.deleteDomain({ accountId, domainId: d.id! });
            }
            yield* Workers.putDomain({
              accountId,
              hostname,
              service: workerName,
              zoneId: STACKPANEL_ZONE,
            });
          }
          return `https://${primary}` as string | undefined;
        }).pipe(Effect.orDie),
      ),
    );
  }

  return {
    url,
    databaseUrl: db.connectionUri,
  };
});

const providers = Layer.mergeAll(
  Cloudflare.providers(),
  neonProviders(),
) as Layer.Layer<any, never, any>;

export default Alchemy.Stack(
  `${PROJECT}-${SERVICE}`,
  {
    providers,
    // dev/PR previews → filesystem state (cached across CI runs);
    // staging/prod → shared Cloudflare-hosted state store.
    state: selectStateBackend(appEnv),
  },
  program,
);
