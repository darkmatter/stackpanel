import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  // Enable static export for Cloudflare deployment
  output: "export",
  // Disable image optimization (not supported in static export)
  images: {
    unoptimized: true,
  },
};

export default withMDX(config);
