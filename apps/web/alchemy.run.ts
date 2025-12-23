import { server } from "@stackpanel/server";
import alchemy from "alchemy";
import { Vite } from "alchemy/cloudflare";
import { config } from "dotenv";

config({ path: "./.env" });

const app = await alchemy("stackpanel");

export const web = await Vite("web", {
  assets: "dist",
  bindings: {
    server,
  },
});

console.log(`Web    -> ${web.url}`);

await app.finalize();
