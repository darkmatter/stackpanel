/**
 * Runtime environment loader for packages/gen/env
 *
 * Loads environment variables from SOPS-encrypted YAML files in data/<app>/<env>.yaml
 * This makes the package portable and self-contained (no dependency on .stackpanel/).
 *
 * Usage:
 *   import { loadEnv } from '@gen/env/loader';
 *
 *   // Load and inject into process.env
 *   await loadEnv('web', 'dev');
 *
 *   // Or get as object without mutating process.env
 *   const env = await loadEnv('web', 'dev', { inject: false });
 *
 * In Docker, ensure:
 *   1. SOPS is installed
 *   2. AGE key is available (SOPS_AGE_KEY_FILE or SOPS_AGE_KEY env var)
 *   3. packages/env/data/ is mounted or copied
 */

import { execSync } from "child_process";
import { existsSync, readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { parse as parseYaml } from "yaml";

const VARIABLE_LINK_PREFIX = "var://";
const groupSecretsCache = new Map<string, Record<string, string>>();

// Get package root directory (works in both ESM and CJS)
const getPackageRoot = (): string => {
  // Try ESM approach
  try {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = dirname(__filename);
    return join(__dirname, "..");
  } catch {
    // Fallback for CJS
    return join(__dirname, "..");
  }
};

export interface LoadEnvOptions {
  /** Inject loaded vars into process.env (default: true) */
  inject?: boolean;
  /** Override the data directory path */
  dataDir?: string;
  /** Skip SOPS decryption (for plaintext files like shared/vars.yaml) */
  skipDecrypt?: boolean;
}

/**
 * Load environment variables from a SOPS-encrypted YAML file.
 *
 * @param app - App name (directory under data/)
 * @param env - Environment name (file name without .yaml)
 * @param options - Loading options
 * @returns Loaded environment variables
 */
export async function loadEnv(
  app: string,
  env: string,
  options: LoadEnvOptions = {},
): Promise<Record<string, string>> {
  const { inject = true, dataDir, skipDecrypt = false } = options;

  const packageRoot = getPackageRoot();
  const baseDataDir = dataDir || join(packageRoot, "data");
  const filePath = join(baseDataDir, app, `${env}.yaml`);

  if (!existsSync(filePath)) {
    throw new Error(`Environment file not found: ${filePath}`);
  }

  let envVars: Record<string, string>;

  if (skipDecrypt) {
    // Load plaintext YAML directly
    const content = readFileSync(filePath, "utf-8");
    envVars = parseYaml(content) || {};
  } else {
    // Decrypt with SOPS
    envVars = decryptSopsFile(filePath);
  }

  // Filter out SOPS metadata
  const filtered = filterSopsMetadata(envVars);

  if (inject) {
    Object.assign(process.env, filtered);
  }

  return filtered;
}

/**
 * Load shared plaintext variables from data/shared/vars.yaml
 */
export async function loadSharedVars(
  options: Omit<LoadEnvOptions, "skipDecrypt"> = {},
): Promise<Record<string, string>> {
  return loadEnv("shared", "vars", { ...options, skipDecrypt: true });
}

/**
 * Load environment for an app, including shared vars.
 * Shared vars are loaded first, then app-specific env (which can override).
 */
export async function loadAppEnv(
  app: string,
  env: string,
  options: LoadEnvOptions = {},
): Promise<Record<string, string>> {
  const packageRoot = getPackageRoot();
  const baseDataDir = options.dataDir || join(packageRoot, "data");

  const shared = await loadSharedVars({
    ...options,
    inject: false,
    dataDir: baseDataDir,
  });
  const rawAppEnv = await loadEnv(app, env, {
    ...options,
    inject: false,
    dataDir: baseDataDir,
  });
  const appEnv = resolveVariableLinks(rawAppEnv, shared, baseDataDir);

  const merged = { ...shared, ...appEnv };

  if (options.inject !== false) {
    Object.assign(process.env, merged);
  }

  return merged;
}

function resolveVariableLinks(
  envVars: Record<string, string>,
  sharedVars: Record<string, string>,
  baseDataDir: string,
): Record<string, string> {
  const resolved: Record<string, string> = { ...envVars };

  for (const [envKey, value] of Object.entries(envVars)) {
    const variableId = parseVariableLink(value);
    if (!variableId) {
      continue;
    }

    const keyGroup = getVariableKeyGroup(variableId);
    const variableName = getVariableName(variableId);

    if (keyGroup === "var") {
      const sharedValue = sharedVars[variableName];
      if (sharedValue === undefined) {
        throw new Error(
          `Could not resolve ${envKey}: linked variable ${variableId} was not found in shared vars`,
        );
      }
      resolved[envKey] = sharedValue;
      continue;
    }

    if (keyGroup === "computed") {
      const computedValue = process.env[variableName];
      if (computedValue === undefined) {
        throw new Error(
          `Could not resolve ${envKey}: linked computed variable ${variableId} is not available at runtime`,
        );
      }
      resolved[envKey] = computedValue;
      continue;
    }

    const groupVars = loadGroupSecrets(baseDataDir, keyGroup);
    const secretValue = groupVars[variableName];
    if (secretValue === undefined) {
      throw new Error(
        `Could not resolve ${envKey}: linked variable ${variableId} was not found in vars/${keyGroup}.sops.yaml`,
      );
    }
    resolved[envKey] = secretValue;
  }

  return resolved;
}

function parseVariableLink(value: string): string | null {
  if (!value.startsWith(VARIABLE_LINK_PREFIX)) {
    return null;
  }

  const rawId = value.slice(VARIABLE_LINK_PREFIX.length).trim();
  if (!rawId) {
    return null;
  }

  return rawId.startsWith("/") ? rawId : `/${rawId}`;
}

function getVariableKeyGroup(variableId: string): string {
  const match = variableId.match(/^\/([^/]+)\//);
  return match?.[1] ?? "var";
}

function getVariableName(variableId: string): string {
  const parts = variableId.split("/").filter(Boolean);
  return parts[parts.length - 1] ?? variableId;
}

function loadGroupSecrets(
  baseDataDir: string,
  keyGroup: string,
): Record<string, string> {
  const sopsFile = findGroupSopsFile(baseDataDir, keyGroup);
  if (!sopsFile) {
    throw new Error(
      `Could not resolve linked variable: missing vars/${keyGroup}.sops.yaml in env package data or source project`,
    );
  }

  const cached = groupSecretsCache.get(sopsFile);
  if (cached) {
    return cached;
  }

  const parsed = filterSopsMetadata(decryptSopsFile(sopsFile));
  groupSecretsCache.set(sopsFile, parsed);
  return parsed;
}

function findGroupSopsFile(baseDataDir: string, keyGroup: string): string | null {
  const explicitSecretsDir = process.env.STACKPANEL_SECRETS_DIR;
  const searchRoots = [
    join(baseDataDir, "vars"),
    explicitSecretsDir ? join(explicitSecretsDir, "vars") : null,
    join(process.cwd(), ".stackpanel", "secrets", "vars"),
  ].filter((root): root is string => Boolean(root));

  for (const root of searchRoots) {
    const candidate = join(root, `${keyGroup}.sops.yaml`);
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return null;
}

/**
 * Decrypt a SOPS-encrypted file using the sops CLI.
 */
function decryptSopsFile(filePath: string): Record<string, string> {
  try {
    // Run sops decrypt
    const result = execSync(`sops -d "${filePath}"`, {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });

    return parseYaml(result) || {};
  } catch (error: any) {
    // Check for common SOPS errors
    if (error.message?.includes("could not decrypt")) {
      throw new Error(
        `Failed to decrypt ${filePath}. Ensure AGE key is available via SOPS_AGE_KEY_CMD, SOPS_AGE_KEY_FILE, or SOPS_AGE_KEY environment variable.`,
      );
    }
    if (
      error.message?.includes("command not found") ||
      error.message?.includes("ENOENT")
    ) {
      throw new Error(
        "SOPS CLI not found. Install it with: brew install sops (macOS) or nix-env -iA nixpkgs.sops",
      );
    }
    throw new Error(`Failed to decrypt ${filePath}: ${error.message}`);
  }
}

/**
 * Filter out SOPS metadata keys from decrypted output.
 */
function filterSopsMetadata(obj: Record<string, any>): Record<string, string> {
  const sopsKeys = [
    "sops",
    "sops_age",
    "sops_azure_kv",
    "sops_gcp_kms",
    "sops_hc_vault",
    "sops_kms",
    "sops_pgp",
  ];
  const filtered: Record<string, string> = {};

  for (const [key, value] of Object.entries(obj)) {
    if (!sopsKeys.includes(key) && typeof value === "string") {
      filtered[key] = value;
    } else if (!sopsKeys.includes(key) && typeof value === "number") {
      filtered[key] = String(value);
    } else if (!sopsKeys.includes(key) && typeof value === "boolean") {
      filtered[key] = String(value);
    }
  }

  return filtered;
}

/**
 * Check if SOPS is available and configured.
 */
export function checkSopsAvailable(): {
  available: boolean;
  keyConfigured: boolean;
  error?: string;
} {
  try {
    execSync("sops --version", { stdio: "pipe" });
  } catch {
    return {
      available: false,
      keyConfigured: false,
      error: "SOPS CLI not found",
    };
  }

  const hasKeyFile = !!process.env.SOPS_AGE_KEY_FILE;
  const hasKeyEnv = !!process.env.SOPS_AGE_KEY;
  const hasKeyCmd = !!process.env.SOPS_AGE_KEY_CMD;

  return {
    available: true,
    keyConfigured: hasKeyFile || hasKeyEnv || hasKeyCmd,
    error:
      !hasKeyFile && !hasKeyEnv && !hasKeyCmd
        ? "No AGE key configured (set SOPS_AGE_KEY_CMD, SOPS_AGE_KEY_FILE or SOPS_AGE_KEY)"
        : undefined,
  };
}
