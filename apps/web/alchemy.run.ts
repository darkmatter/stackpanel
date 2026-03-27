import alchemy from "alchemy";
import { TanStackStart } from "alchemy/cloudflare";
import { CloudflareStateStore } from "alchemy/state";
import { config } from "dotenv";
import type { StackpanelDB } from "@/lib/generated/nix-types";

export const spStatePath = `${process.env.STACKPANEL_ROOT}/state/stackpanel.json`;
const cfg: StackpanelDB = await Bun.file(spStatePath).json();
const awscfg = cfg.aws?.["roles-anywhere"];
if (awscfg) {
  console.log(`AWS Config has keys: ${Object.keys(awscfg).join(", ")}`);
}

config({ path: "./.env" });

const app = await alchemy("stackpanel", {
  stage: "shared",
  stateStore: (scope) =>
    new CloudflareStateStore(scope, {
      apiToken: alchemy.secret(process.env.CLOUDFLARE_API_TOKEN!),
    }),
});

export const web = await TanStackStart("web", {
  bindings: {
    DATABASE_URL: alchemy.secret.env.DATABASE_URL,
    CORS_ORIGIN: alchemy.env.CORS_ORIGIN,
    BETTER_AUTH_SECRET: alchemy.secret.env.BETTER_AUTH_SECRET,
    BETTER_AUTH_URL: alchemy.env.BETTER_AUTH_URL,
    POLAR_ACCESS_TOKEN: alchemy.secret.env.POLAR_ACCESS_TOKEN,
    POLAR_SUCCESS_URL: alchemy.env.POLAR_SUCCESS_URL,
  },
});

console.log(`Web    -> ${web.url}`);

await app.finalize();
