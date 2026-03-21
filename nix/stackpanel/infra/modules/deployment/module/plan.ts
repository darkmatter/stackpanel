export interface AppInput {
  framework: string;
  host: string;
  path: string;
  bindings: string[];
  secrets: string[];
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
    };

export function buildDeploymentPlan(
  appName: string,
  app: AppInput,
): DeploymentPlan {
  if (app.host !== "cloudflare") {
    throw new Error(
      `Unsupported host "${app.host}" in deployment plan builder`,
    );
  }

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
}
