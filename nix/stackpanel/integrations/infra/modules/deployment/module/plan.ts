// =============================================================================
// plan.ts — Deployment plan types and builder
//
// Translates the Nix-provided per-app config (framework + host) into a
// concrete DeploymentPlan that the orchestrator (index.ts) dispatches on.
//
// The plan is a discriminated union on `kind` so the orchestrator gets
// type-safe access to host-specific fields.
// =============================================================================

/** Per-app config as serialized from Nix via infra-inputs.json. */
export interface AppInput {
  framework: string;
  host: string;
  path: string;
  /** Environment variable names to bind (both plaintext and secrets). */
  bindings: string[];
  /** Subset of bindings that should be stored as SecureString in SSM. */
  secrets: string[];

  /** AWS-specific config (only present when host === "aws"). */
  aws?: {
    region?: string | null;
    availabilityZone?: string | null;
    imageId?: string | null;
    instanceType?: string | null;
    keyName?: string | null;
    port?: number | null;
    parameterPath?: string | null;
    httpCidrBlocks?: string[];
    sshCidrBlocks?: string[];
    rootVolumeSize?: number | null;
    vpcCidrBlock?: string | null;
    subnetCidrBlock?: string | null;
    tags?: Record<string, string>;
    /** "amazon-linux" uses tarball + UserData bootstrap; "nixos" uses static boot + Colmena. */
    osType?: "amazon-linux" | "nixos";
  };

  /** Cloudflare-specific config (only present when host === "cloudflare"). */
  cloudflare?: {
    workerName?: string;
    route?: string | null;
    compatibility?: "node" | "browser";
  };

  /** Framework-specific overrides (present regardless of host). */
  ssr?: boolean;
  assetsDir?: string;
  entrypoint?: string;
  output?: string;
}

/** Global deployment config from stackpanel.deployment.* in Nix. */
export interface DeploymentInputs {
  apps: Record<string, AppInput>;
  aws?: {
    region?: string | null;
    instanceType?: string | null;
    port?: number | null;
    artifact?: {
      bucket?: string | null;
      keyPrefix?: string | null;
    };
  };
  cloudflare?: {
    compatibilityDate?: string | null;
    defaultRoute?: string | null;
  };
}

/**
 * Discriminated union describing how to deploy a single app.
 * The orchestrator switches on `kind` to call the right deploy function.
 */
export type DeploymentPlan =
  | {
      kind: "cloudflare-nextjs-app";
      appScopeName: string;
      cwd: string;
      resourceName: "website";
    }
  | {
      kind: "cloudflare-app";
      appScopeName: string;
      cwd: string;
      framework: string;
      resourceName: string;
    }
  | {
      kind: "aws-ec2-app";
      appScopeName: string;
      cwd: string;
      resourceName: string;
    };

/** Map (framework, host) -> DeploymentPlan for a single app. */
export function buildDeploymentPlan(
  appName: string,
  app: AppInput,
): DeploymentPlan {
  switch (app.host) {
    case "cloudflare":
      if (app.framework === "nextjs") {
        return {
          kind: "cloudflare-nextjs-app",
          appScopeName: appName,
          cwd: app.path,
          resourceName: "website",
        };
      }

      return {
        kind: "cloudflare-app",
        appScopeName: appName,
        cwd: app.path,
        framework: app.framework,
        resourceName: appName,
      };

    case "aws":
      return {
        kind: "aws-ec2-app",
        appScopeName: appName,
        cwd: app.path,
        resourceName: appName,
      };

    default:
      throw new Error(
        `Unsupported host "${app.host}" in deployment plan builder`,
      );
  }
}
