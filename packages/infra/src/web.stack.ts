// Web deployment is now handled by apps/web/alchemy.run.ts directly.
// This file re-exports the NeonProject resource for use by other packages.
export { NeonProject, neonProviders } from "./resources/neon";
