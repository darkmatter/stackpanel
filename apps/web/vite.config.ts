import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import alchemy from "alchemy/cloudflare/tanstack-start";
import { nitro } from "nitro/vite";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

// ALCHEMY=1 is set by root alchemy.run.ts for builds/deploys
const useAlchemy = process.env.ALCHEMY === "1";

export default defineConfig({
	plugins: [
		tsconfigPaths({
			projects: ["./tsconfig.json"],
		}),
		tailwindcss(),
		// Use alchemy for Cloudflare deployment, nitro for local dev (HMR)
		...(useAlchemy ? [alchemy()] : [nitro()]),
		tanstackStart(),
		viteReact(),
	],
	server: {
		port: 3001,
		host: "0.0.0.0",
		allowedHosts: ["coopers-mac-studio"],
	},
});
