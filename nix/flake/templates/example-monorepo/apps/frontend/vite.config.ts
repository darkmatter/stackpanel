import react from "@vitejs/plugin-react";
import alchemy from "alchemy/cloudflare/vite";
import { defineConfig, type PluginOption } from "vite-plus";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), alchemy() as PluginOption],
});
