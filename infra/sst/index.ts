/// <reference path="../../.sst/platform/config.d.ts" />

/**
 * SST Infrastructure Modules
 *
 * This is the main entry point for all SST infrastructure code.
 */

// Apps
export { createDocs, createWebApp } from "./apps";
// Configuration
export { config, getDomain, getEnvironment } from "./config";
// Secrets
export { createSecrets, type Secrets } from "./secrets";

// Utilities
export { SopsOutput } from "./sops-output";
