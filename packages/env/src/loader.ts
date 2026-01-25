/**
 * Runtime environment loader for packages/env
 * 
 * Loads environment variables from SOPS-encrypted YAML files in data/<app>/<env>.yaml
 * This makes the package portable and self-contained (no dependency on .stackpanel/).
 * 
 * Usage:
 *   import { loadEnv } from '@stackpanel/env/loader';
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

import { execSync } from 'child_process';
import { existsSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { parse as parseYaml } from 'yaml';

// Get package root directory (works in both ESM and CJS)
const getPackageRoot = (): string => {
  // Try ESM approach
  try {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = dirname(__filename);
    return join(__dirname, '..');
  } catch {
    // Fallback for CJS
    return join(__dirname, '..');
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
  options: LoadEnvOptions = {}
): Promise<Record<string, string>> {
  const { inject = true, dataDir, skipDecrypt = false } = options;
  
  const packageRoot = getPackageRoot();
  const baseDataDir = dataDir || join(packageRoot, 'data');
  const filePath = join(baseDataDir, app, `${env}.yaml`);
  
  if (!existsSync(filePath)) {
    throw new Error(`Environment file not found: ${filePath}`);
  }
  
  let envVars: Record<string, string>;
  
  if (skipDecrypt) {
    // Load plaintext YAML directly
    const content = readFileSync(filePath, 'utf-8');
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
  options: Omit<LoadEnvOptions, 'skipDecrypt'> = {}
): Promise<Record<string, string>> {
  return loadEnv('shared', 'vars', { ...options, skipDecrypt: true });
}

/**
 * Load environment for an app, including shared vars.
 * Shared vars are loaded first, then app-specific env (which can override).
 */
export async function loadAppEnv(
  app: string,
  env: string,
  options: LoadEnvOptions = {}
): Promise<Record<string, string>> {
  const shared = await loadSharedVars({ ...options, inject: false });
  const appEnv = await loadEnv(app, env, { ...options, inject: false });
  
  const merged = { ...shared, ...appEnv };
  
  if (options.inject !== false) {
    Object.assign(process.env, merged);
  }
  
  return merged;
}

/**
 * Decrypt a SOPS-encrypted file using the sops CLI.
 */
function decryptSopsFile(filePath: string): Record<string, string> {
  try {
    // Run sops decrypt
    const result = execSync(`sops -d "${filePath}"`, {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    
    return parseYaml(result) || {};
  } catch (error: any) {
    // Check for common SOPS errors
    if (error.message?.includes('could not decrypt')) {
      throw new Error(
        `Failed to decrypt ${filePath}. Ensure AGE key is available via SOPS_AGE_KEY_FILE or SOPS_AGE_KEY environment variable.`
      );
    }
    if (error.message?.includes('command not found') || error.message?.includes('ENOENT')) {
      throw new Error(
        'SOPS CLI not found. Install it with: brew install sops (macOS) or nix-env -iA nixpkgs.sops'
      );
    }
    throw new Error(`Failed to decrypt ${filePath}: ${error.message}`);
  }
}

/**
 * Filter out SOPS metadata keys from decrypted output.
 */
function filterSopsMetadata(obj: Record<string, any>): Record<string, string> {
  const sopsKeys = ['sops', 'sops_age', 'sops_azure_kv', 'sops_gcp_kms', 'sops_hc_vault', 'sops_kms', 'sops_pgp'];
  const filtered: Record<string, string> = {};
  
  for (const [key, value] of Object.entries(obj)) {
    if (!sopsKeys.includes(key) && typeof value === 'string') {
      filtered[key] = value;
    } else if (!sopsKeys.includes(key) && typeof value === 'number') {
      filtered[key] = String(value);
    } else if (!sopsKeys.includes(key) && typeof value === 'boolean') {
      filtered[key] = String(value);
    }
  }
  
  return filtered;
}

/**
 * Check if SOPS is available and configured.
 */
export function checkSopsAvailable(): { available: boolean; keyConfigured: boolean; error?: string } {
  try {
    execSync('sops --version', { stdio: 'pipe' });
  } catch {
    return { available: false, keyConfigured: false, error: 'SOPS CLI not found' };
  }
  
  const hasKeyFile = !!process.env.SOPS_AGE_KEY_FILE;
  const hasKeyEnv = !!process.env.SOPS_AGE_KEY;
  
  return {
    available: true,
    keyConfigured: hasKeyFile || hasKeyEnv,
    error: !hasKeyFile && !hasKeyEnv ? 'No AGE key configured (set SOPS_AGE_KEY_FILE or SOPS_AGE_KEY)' : undefined,
  };
}
