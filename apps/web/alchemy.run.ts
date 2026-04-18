import { loadAppEnv } from "@gen/env/runtime";
import { NeonProject, neonProviders } from "@stackpanel/infra/resources/neon";
import { Cloudflare, Output, Stage } from "alchemy-effect";
import * as Stack from "alchemy-effect/Stack";
import * as Workers from "@distilled.cloud/cloudflare/workers";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";


const APP_ENV = process.env.APP_ENV || "dev";
const PROJECT = "stackpanel";
const SERVICE = "web";
const env = await loadAppEnv(SERVICE, APP_ENV, { inject: true });

if (!env.CLOUDFLARE_API_TOKEN) {
  throw new Error(`
!! Missing required environment variable: CLOUDFLARE_API_TOKEN !!
- Most likely, you need to wrap your command, for example:
   \`sops exec-env .secrets.enc.yaml 'bun run -F ${PROJECT} alchemy.run.ts'\`
- Or export the variable directly.`);
}

const STACKPANEL_ZONE = "d34628a3ab639230ff1f6dc1eb640eec"; // stackpanel.com

const program = Effect.gen(function* () {
  const stage = yield* Stage;

  const db = yield* NeonProject("postgres", {
    name: `${PROJECT}-${stage}`,
    regionId: "aws-us-east-1",
    pgVersion: 17,
    databaseName: `${SERVICE}_${stage}`,
    roleName: `${PROJECT}-${SERVICE}-owner`,
  });

  const website = yield* Cloudflare.Vite("TanstackStart", {
    compatibility: {
      flags: ["nodejs_compat"],
    },
    env: {
      DATABASE_URL: db.connectionUri,
    },
  });
  let url: Output.Output<string | undefined> = website.url;

  if (stage !== "dev") {
    const hostname =
      stage === "production" ? "stackpanel.com" : `${stage}.stackpanel.com`;
    url = Output.all(website.accountId, website.workerName).pipe(
      Output.mapEffect(([accountId, workerName]) =>
        Effect.gen(function* () {
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
          return `https://${hostname}` as string | undefined;
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

export default Stack.make(`${PROJECT}-${SERVICE}`, providers)(program);
