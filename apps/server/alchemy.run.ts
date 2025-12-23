import path from "node:path";
import alchemy from "alchemy";
import { Worker } from "alchemy/cloudflare";

const app = await alchemy("stackpanel");

// Only provision Neon in production (deploy), skip in dev mode
if (!app.local) {
  const { NeonProject } = await import("alchemy/neon");
  const db = await NeonProject("db", {
    name: "stackpanel",
  });
}

export const server = await Worker("worker", {
  entrypoint: path.join(import.meta.dirname, "src", "index.ts"),
  dev: {
    port: Number.parseInt(process.env.PORT_SERVER || "6401"),
  },
});
console.log(`Server    -> ${server.url}`);

await app.finalize();
