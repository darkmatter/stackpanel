// Auto-generated entrypoint for {{APP_NAME}} — do not edit manually.
// Loads environment-specific secrets at runtime.
import { loadAppEnv } from "../loader";

const ENV = process.env.NODE_ENV || process.env.APP_ENV || "dev";

const validEnvs = {{VALID_ENVS}};
if (!validEnvs.includes(ENV)) {
  console.warn(`Unknown environment: ${ENV}. Using 'dev'.`);
}

export async function init() {
  const env = validEnvs.includes(ENV) ? ENV : "dev";
  await loadAppEnv("{{APP_NAME}}", env);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  init().catch(console.error);
}
