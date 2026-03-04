// Auto-generated entrypoint for stackpanel-go
// Loads environment-specific secrets at runtime
import { loadAppEnv } from '../loader';

const ENV = process.env.NODE_ENV || process.env.APP_ENV || 'dev';

// Validate environment
const validEnvs = ["dev"];
if (!validEnvs.includes(ENV)) {
  console.warn(`Unknown environment: ${ENV}. Using 'dev'.`);
}

// Load secrets for this app/environment
export async function init() {
  const env = validEnvs.includes(ENV) ? ENV : 'dev';
  await loadAppEnv('stackpanel-go', env);
}

// Auto-initialize if this is the main module
if (import.meta.url === `file://${process.argv[1]}`) {
  init().catch(console.error);
}
