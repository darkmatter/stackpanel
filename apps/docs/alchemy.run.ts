import alchemy from "alchemy";
import { Nextjs } from "alchemy/cloudflare";

if (!process.env.CLOUDFLARE_API_TOKEN) {
  throw new Error(`
!! Missing required environment variable: CLOUDFLARE_API_TOKEN !!
- Export the variable directly or pass it via CI secrets.`);
}

const stage = process.env.STAGE ?? "production";

const app = await alchemy("stackpanel-docs", {
  stage,
  phase: process.argv.includes("destroy") ? "destroy" : "up",
});

export const website = await Nextjs("docs", {
  adopt: true,
});

console.log(`deployed to ${website.url}`);

await app.finalize();
