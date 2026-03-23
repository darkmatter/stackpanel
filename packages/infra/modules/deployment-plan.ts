export interface AppInput {
  framework: string;
  host: string;
  path: string;
  bindings: string[];
  secrets: string[];
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
  };
  cloudflare?: {
    workerName?: string;
    route?: string | null;
    compatibility?: "node" | "browser";
  };
  ssr?: boolean;
  assetsDir?: string;
  entrypoint?: string;
  output?: string;
}

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
