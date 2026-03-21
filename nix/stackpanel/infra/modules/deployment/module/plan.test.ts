import { describe, expect, test } from "bun:test";
import { buildDeploymentPlan } from "./plan";

describe("buildDeploymentPlan", () => {
  test("uses app-scoped Alchemy plan for Cloudflare Next.js apps", () => {
    const plan = buildDeploymentPlan("docs", {
      bindings: ["ASSET_HOST"],
      framework: "nextjs",
      host: "cloudflare",
      path: "apps/docs",
      secrets: [],
      cloudflare: {
        compatibility: "node",
        workerName: "stackpanel-docs",
      },
    });

    expect(plan.kind).toBe("cloudflare-nextjs-app");
    expect(plan.appScopeName).toBe("docs");
    expect(plan.resourceName).toBe("website");
    expect(plan.cwd).toBe("apps/docs");
  });
});
