import { initOpenNextCloudflareForDev } from "@opennextjs/cloudflare";
import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  experimental: {
    reactCompiler: true,
  },
  // Enable static export for Cloudflare deployment
  output: "export",
  // Disable image optimization (not supported in static export)
  images: {
    unoptimized: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
};

export default withMDX(config);

initOpenNextCloudflareForDev();
