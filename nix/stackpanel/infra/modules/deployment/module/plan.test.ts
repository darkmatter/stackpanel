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

  test("uses aws ec2 plan for AWS-hosted apps", () => {
    const plan = buildDeploymentPlan("web", {
      bindings: ["DATABASE_URL", "BETTER_AUTH_SECRET"],
      framework: "tanstack-start",
      host: "aws",
      path: "apps/web",
      secrets: ["DATABASE_URL", "BETTER_AUTH_SECRET"],
      aws: {
        instanceType: "t3.small",
        port: 80,
        region: "us-west-2",
      },
    });

    expect(plan.kind).toBe("aws-ec2-app");
    expect(plan.appScopeName).toBe("web");
    expect(plan.resourceName).toBe("web");
    expect(plan.cwd).toBe("apps/web");
  });
});
