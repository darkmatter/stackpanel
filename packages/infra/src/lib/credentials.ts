import { fromApiToken } from "@distilled.cloud/cloudflare";
import * as Redacted from "effect/Redacted";

if (!process.env.CLOUDFLARE_API_TOKEN) {
  throw new Error(`
!! Missing required environment variable: CLOUDFLARE_API_TOKEN !!
- Most likely, you need to wrap your command, for example:
   \`sops exec-env .secrets.enc.yaml 'bun run -F web alchemy.run.ts'\`
- Or export the variable directly.`);
}

export const cloudflareCredentials = fromApiToken({
  apiToken: Redacted.make(process.env.CLOUDFLARE_API_TOKEN),
});
