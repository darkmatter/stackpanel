import alchemy from "alchemy";
import { execSync } from "node:child_process";
import { Nextjs, KVNamespace } from "alchemy/cloudflare";
import { CloudflareStateStore } from "alchemy/state";
import { Exec } from "alchemy/os";
import { createAlchemyFileModule } from "@stackpanel/sdk/sops";

const CLOUDFLARE_API_TOKEN = execSync(
  "chamber read infra cloudflare-api-token -q",
)
  .toString()
  .trim();

const files = createAlchemyFileModule();

const stateToken = await files.readSecret(
  "ref+sops://.stack/secrets/vars/common.sops.yaml#/alchemy-state-token",
);

const app = await alchemy("docs", {
  stateStore: (scope) =>
    new CloudflareStateStore(scope, {
      stateToken,
      apiToken: alchemy.secret(CLOUDFLARE_API_TOKEN),
    }),
});

export const kv = await KVNamespace("kv");

export const website = await Nextjs("docs", {
  adopt: true,
  bindings: {
    KV: kv,
  },
});

console.log(`deployed to ${website.url}`);

await app.finalize();
