import { Polar } from "@polar-sh/sdk";
import { polarAccessToken, presentRedacted } from "../config";

// Polar client for payment processing. Optional — only constructed when
// `POLAR_ACCESS_TOKEN` is set (and non-empty) at module load. Read via
// `effect/Config` from `process.env`, which the deploy pipeline populates
// at build time (see `docs/adr/0003-build-time-env-injection-with-effect-config.md`).
const accessToken = presentRedacted(polarAccessToken);

export const polarClient = accessToken
  ? new Polar({
      accessToken,
      server: "sandbox",
    })
  : null;
