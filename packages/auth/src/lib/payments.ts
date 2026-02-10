import { Polar } from "@polar-sh/sdk";
import { env } from "@gen/env/web";

// Polar client for payment processing (optional - only used if POLAR_ACCESS_TOKEN is set)
export const polarClient = env.POLAR_ACCESS_TOKEN
  ? new Polar({
      accessToken: env.POLAR_ACCESS_TOKEN,
      server: "sandbox",
    })
  : null;
