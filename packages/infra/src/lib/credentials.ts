import { loadAppEnv } from "@gen/env/runtime";
import { fromApiToken } from "@distilled.cloud/cloudflare";

if (!process.env.CLOUDFLARE_API_TOKEN) {
  throw new Error(`
!! Missing required environment variable: CLOUDFLARE_API_TOKEN !!
- Most likely, you need to wrap your command, for example:
   \`sops exec-env .secrets.enc.yaml 'bun run -F web alchemy.run.ts'\`
- Or export the variable directly.`);
}

const env = await loadAppEnv("web", process.env.APP_ENV || "dev");

export const cloudflareCredentials = fromApiToken({
  apiToken: env.CLOUDFLARE_API_TOKEN,
});
