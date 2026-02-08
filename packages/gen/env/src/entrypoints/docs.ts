// Auto-generated entrypoint for docs — do not edit manually.
// Loads environment-specific secrets at runtime.
import { loadAppEnv } from "../loader";

const ENV = process.env.NODE_ENV || process.env.APP_ENV || "dev";

const validEnvs = ["dev","prod","staging"];
if (!validEnvs.includes(ENV)) {
  console.warn(`Unknown environment: ${ENV}. Using 'dev'.`);
}

export async function init() {
  const env = validEnvs.includes(ENV) ? ENV : "dev";
  await loadAppEnv("docs", env);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  init().catch(console.error);
}
