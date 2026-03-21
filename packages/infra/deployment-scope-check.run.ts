import path from "node:path";
import { fileURLToPath } from "node:url";
import alchemy from "alchemy";

process.chdir(
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", ".."),
);

const app = await alchemy("stackpanel-deployment-scope-check");

const outputs = (await import("./modules/deployment/index.ts")).default;

console.log(outputs);

await app.finalize();
