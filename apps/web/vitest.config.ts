import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";
import { defineConfig } from "vitest/config";

// Calculate repo root from this config file's location
// This file is at: apps/web/vitest.config.ts
// Repo root is 2 levels up
const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..");

export default defineConfig({
	plugins: [react(), tsconfigPaths()],
	test: {
		environment: "happy-dom",
		globals: true,
		include: ["src/**/*.{test,spec}.{ts,tsx}"],
		exclude: ["node_modules", "dist", ".alchemy"],
		coverage: {
			provider: "v8",
			reporter: ["text", "json", "html"],
			exclude: [
				"node_modules",
				"dist",
				".alchemy",
				"**/*.d.ts",
				"**/*.config.*",
				"**/types.ts",
				"**/generated/**",
				"**/test/integration/**",
			],
		},
		setupFiles: ["./src/test/setup.ts"],
		// Environment variables for tests
		env: {
			STACKPANEL_REPO_ROOT: repoRoot,
		},
		// Longer timeout for integration tests
		testTimeout: 10000,
		// Run tests sequentially to avoid port conflicts in integration tests
		sequence: {
			concurrent: false,
		},
	},
});
