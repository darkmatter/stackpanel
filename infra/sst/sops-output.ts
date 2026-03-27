/**
 * SOPS Output Component
 *
 * Writes SST outputs to a SOPS-encrypted YAML file.
 * Requires SOPS to be installed and configured with .sops.yaml
 */

/// <reference path="../../.sst/platform/config.d.ts" />

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

interface SopsOutputArgs {
	/**
	 * Path to the output file (will be encrypted)
	 */
	path: string;

	/**
	 * Key-value pairs to write to the file
	 * Values can be Pulumi Outputs or plain strings
	 */
	values: Record<string, $util.Input<string | undefined>>;
}

/**
 * Write outputs to a SOPS-encrypted YAML file
 *
 * Usage:
 * ```ts
 * new SopsOutput("Secrets", {
 *   path: `.stack/secrets/${stage}.yaml`,
 *   values: {
 *     database_url: secrets.databaseUrl.value,
 *     web_url: workers.us.url,
 *   },
 * });
 * ```
 */
export class SopsOutput {
	constructor(name: string, args: SopsOutputArgs) {
		// Resolve all values at once using $resolve with the values object
		$resolve(args.values).apply((resolved) => {
			const lines = Object.entries(resolved).map(([key, value]) =>
				value !== undefined ? `${key}: "${value}"` : `# ${key}: (not set)`,
			);
			const content = lines.join("\n");

			const tmpPath = `${args.path}.tmp`;
			const dir = path.dirname(args.path);

			// Ensure directory exists
			if (!fs.existsSync(dir)) {
				fs.mkdirSync(dir, { recursive: true });
			}

			// Write temp file
			fs.writeFileSync(tmpPath, content);

			try {
				// Encrypt with SOPS
				execSync(`sops --encrypt "${tmpPath}" > "${args.path}"`, {
					stdio: "pipe",
				});
				console.log(`✓ Wrote encrypted secrets to ${args.path}`);
			} catch (err) {
				console.error(`✗ Failed to encrypt ${args.path}:`, err);
				// Leave unencrypted file for debugging
				fs.renameSync(tmpPath, args.path);
				console.log(`  Wrote unencrypted file for debugging`);
				return;
			}

			// Clean up temp file
			if (fs.existsSync(tmpPath)) {
				fs.unlinkSync(tmpPath);
			}
		});
	}
}

/**
 * Helper: Write outputs synchronously (for use outside SST)
 */
export function writeSopsSync(
	filePath: string,
	values: Record<string, string | undefined>,
): void {
	const yaml = Object.entries(values)
		.filter(([_, v]) => v !== undefined)
		.map(([k, v]) => `${k}: "${v}"`)
		.join("\n");

	const tmpPath = `${filePath}.tmp`;
	const dir = path.dirname(filePath);

	if (!fs.existsSync(dir)) {
		fs.mkdirSync(dir, { recursive: true });
	}

	fs.writeFileSync(tmpPath, yaml);

	try {
		execSync(`sops --encrypt "${tmpPath}" > "${filePath}"`, {
			stdio: "inherit",
		});
	} finally {
		if (fs.existsSync(tmpPath)) {
			fs.unlinkSync(tmpPath);
		}
	}

	console.log(`✓ Wrote encrypted secrets to ${filePath}`);
}
