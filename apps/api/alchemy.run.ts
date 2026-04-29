// apps/api/alchemy.run.ts
//
// Declarative cert + DNS orchestration for the api on Fly.
//
// The Fly machine is built and deployed by the CI workflow's
// `bun run build` → `nix build container-api` → skopeo push → flyctl
// deploy chain. This script handles the things that *aren't* the machine:
//
//   1. Ensure an ACME certificate for the public hostname exists on the
//      Fly app (idempotent).
//   2. Look up the IP addresses Fly assigned to the app.
//   3. Create A + AAAA records on the stackpanel.com Cloudflare zone
//      pointing at those IPs (proxy off — Fly terminates TLS).
//
// Replaces the previous `flyctl certs add` + manual Cloudflare DNS
// dance. Same Effect-native pattern as apps/web's domain binding via
// `@distilled.cloud/cloudflare` Workers.

import { loadDeployEnv, resolveDeployStage } from "@stackpanel/infra/lib/deploy";
import {
  AppCertificatesAcmeCreate,
  AppIPAssignmentsList,
} from "@distilled.cloud/fly-io/Operations";
import { CredentialsFromEnv as FlyCredentialsFromEnv } from "@distilled.cloud/fly-io";
import * as DNS from "@distilled.cloud/cloudflare/dns";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

const PROJECT = "stackpanel";
const SERVICE = "api";

const FLY_APP = "stackpanel-api";
const STACKPANEL_ZONE = "d34628a3ab639230ff1f6dc1eb640eec";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); CI sets
// FLY_IO_API_KEY from the FLY_API_TOKEN GH secret so the fly-io SDK
// picks it up via process.env.
const { stage, appEnv } = resolveDeployStage();
await loadDeployEnv(SERVICE, appEnv);

// Production lives at api.stackpanel.com; preview/staging deploys get
// api-<stage>.stackpanel.com so they don't collide with prod.
const hostnameFor = (stage: string): string =>
  stage === "production" ? "api.stackpanel.com" : `api-${stage}.stackpanel.com`;

const program = Effect.gen(function* () {
  if (stage === "dev") {
    // Local/dev deploys serve from stackpanel-api.fly.dev directly — no
    // custom hostname, no DNS records.
    return { url: `https://${FLY_APP}.fly.dev` };
  }

  const hostname = hostnameFor(stage);

  // (1) Ensure ACME cert exists for the hostname. Idempotent: returns
  // the existing cert if one's already on the app.
  yield* AppCertificatesAcmeCreate({ app_name: FLY_APP, hostname });

  // (2) Look up the IPs Fly assigned the app. Shared v4 + dedicated v6
  // is the default. We point DNS at whatever Fly returns rather than
  // hard-coding 66.241.125.29.
  const ipsResp = (yield* AppIPAssignmentsList({ app_name: FLY_APP })) as {
    ips?: ReadonlyArray<{ ip?: string; service_name?: string; shared?: boolean }>;
  };
  const ips = ipsResp.ips ?? [];
  // Fly returns one row per assigned IP. Distinguish v4 (IPv4 dotted quad)
  // from v6 (contains a colon) at the address level rather than relying on
  // a `kind` field that the SDK schema doesn't expose.
  const v4 = ips.find((i) => i.ip && !i.ip.includes(":"))?.ip;
  const v6 = ips.find((i) => i.ip && i.ip.includes(":"))?.ip;
  if (!v4 || !v6) {
    return yield* Effect.fail(
      new Error(
        `Fly app ${FLY_APP} missing v4 or v6 IP (got: ${JSON.stringify(ips)})`,
      ),
    );
  }

  // (3) Reconcile DNS records: drop anything stale at this name, then
  // create the A + AAAA pointing at Fly. Proxy off — Fly's ACME validation
  // and TLS termination both need direct connections, not the CF proxy.
  const existing = (yield* DNS.listRecords({
    zoneId: STACKPANEL_ZONE,
    name: { exact: hostname },
  } as never)) as { result?: ReadonlyArray<{ id: string; name?: string; type?: string }> };
  for (const r of existing.result ?? []) {
    if (r.name === hostname && (r.type === "A" || r.type === "AAAA")) {
      yield* DNS.deleteRecord({ zoneId: STACKPANEL_ZONE, dnsRecordId: r.id });
    }
  }
  yield* DNS.createRecord({
    zoneId: STACKPANEL_ZONE,
    name: hostname,
    type: "A",
    content: v4,
    ttl: 1,
    proxied: false,
  });
  yield* DNS.createRecord({
    zoneId: STACKPANEL_ZONE,
    name: hostname,
    type: "AAAA",
    content: v6,
    ttl: 1,
    proxied: false,
  } as never);

  return { url: `https://${hostname}` };
});

// Both providers' credentials read from process.env (set by loadDeployEnv).
const providers = Layer.mergeAll(FlyCredentialsFromEnv) as unknown as Layer.Layer<
  any,
  never,
  any
>;

export default Alchemy.Stack(
  `${PROJECT}-${SERVICE}`,
  {
    providers,
    state: Cloudflare.state(),
  },
  program,
);
