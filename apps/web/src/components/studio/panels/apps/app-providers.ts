import type { NixPanel } from "../shared/panel-types";
import {
  getRootStudioPanels,
  studioPanelKey,
  studioPanelMatchesApp,
} from "../shared/use-studio-panels";

export type ProviderKind = "runtime" | "framework";

export interface AppProvider {
  id: string;
  module: string;
  label: string;
  enabled: boolean;
  compatibleRuntimes: string[];
}

export type AppProviders = Record<ProviderKind, AppProvider[]>;

// PatchNixData accepts dotted paths with backslash-escaped literal segments.
export function appPathSegment(id: string): string {
  return id.replaceAll("\\", "\\\\").replaceAll(".", "\\.");
}

function record(value: unknown): Record<string, unknown> | undefined {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return undefined;
}

/** Provider registries describe choices; the evaluated app, not its display type, owns selection. */
export function getAppProviders(
  config: Record<string, unknown> | null,
  appId: string | null,
  enabledModules: ReadonlyMap<string, unknown>,
): AppProviders | null {
  // A new app has no enabled providers yet. A missing existing app is not the same thing.
  const app: Record<string, unknown> | undefined =
    appId === null ? {} : record(record(config?.apps)?.[appId]);
  const runtimes = record(config?.appRuntimes);
  const frameworks = record(config?.appFrameworks);
  if (!app || !runtimes || !frameworks) return null;

  function choices(
    registry: Record<string, unknown>,
    options: Record<string, unknown> | undefined,
    kind: ProviderKind,
  ): AppProvider[] | null {
    const choices: AppProvider[] = [];
    for (const [id, value] of Object.entries(registry)) {
      const provider = record(value);
      if (!provider || typeof provider.module !== "string" || !provider.module) return null;
      if (!enabledModules.has(provider.module)) continue;
      const compatible = kind === "framework" ? provider.compatibleRuntimes : [];
      if (!Array.isArray(compatible) || !compatible.every((id) => typeof id === "string")) return null;
      choices.push(
        {
          id,
          module: provider.module,
          label: typeof provider?.label === "string" ? provider.label : id,
          enabled: record(options?.[id])?.enable === true,
          compatibleRuntimes: compatible,
        },
      );
    }
    return choices;
  }

  const runtime = choices(runtimes, app, "runtime");
  const framework = choices(frameworks, record(app.framework), "framework");
  return runtime && framework ? { runtime, framework } : null;
}

function supportsRuntime(framework: AppProvider, runtimeIds: string[]): boolean {
  return (
    runtimeIds.length === 0 ||
    framework.compatibleRuntimes.length === 0 ||
    runtimeIds.some((id) => framework.compatibleRuntimes.includes(id))
  );
}

export function compatibleFrameworks(providers: AppProviders): AppProvider[] {
  const runtimeIds = providers.runtime.filter((p) => p.enabled).map((p) => p.id);
  return providers.framework.filter((framework) => supportsRuntime(framework, runtimeIds));
}

interface EnablePatch {
  path: string;
  enabled: boolean;
}

/** Only touch enable flags, never replace the provider's app-specific options. */
export function planProviderChange(
  providers: AppProviders,
  kind: ProviderKind,
  next: string | null,
): EnablePatch[] {
  const choices = kind === "framework" ? compatibleFrameworks(providers) : providers.runtime;
  if (next !== null && !choices.some((p) => p.id === next)) {
    throw new Error(`Unavailable ${kind}: ${next}`);
  }

  const patches: EnablePatch[] = [];
  function patch(target: ProviderKind, id: string, enabled: boolean) {
    const segment = appPathSegment(id);
    patches.push({
      path: `${target === "framework" ? "framework." : ""}${segment}.enable`,
      enabled,
    });
  }

  // Keep intermediate states valid as PatchNixData commits one field at a time.
  if (kind === "runtime" && next !== null) {
    for (const framework of providers.framework) {
      if (framework.enabled && !supportsRuntime(framework, [next]))
        patch("framework", framework.id, false);
    }
  }
  for (const provider of providers[kind]) {
    if (provider.enabled && provider.id !== next) patch(kind, provider.id, false);
  }
  if (next !== null && !providers[kind].some((p) => p.id === next && p.enabled))
    patch(kind, next, true);
  return patches;
}

export interface AppPanelMounts {
  runtime: NixPanel[];
  framework: NixPanel[];
  tabs: NixPanel[];
}

export function getAppPanelMounts(
  panels: NixPanel[],
  appId: string,
  providers: AppProviders | null,
): AppPanelMounts {
  const mounts: AppPanelMounts = { runtime: [], framework: [], tabs: [] };
  const frameworks = providers ? compatibleFrameworks(providers) : [];
  const seen = new Set<string>();
  // Resolve nested-tab ownership only after applying this app's eligibility:
  // a group exclusive to app A must not hide its child in app B.
  const roots = getRootStudioPanels(
    panels.filter((panel) => panel.enabled && studioPanelMatchesApp(panel, appId)),
  );
  for (const panel of roots) {
    const key = studioPanelKey(panel);
    if (seen.has(key)) continue;
    switch (panel.slot) {
      case "app:runtime":
        if (providers?.runtime.some((p) => p.enabled && p.module === panel.module))
          mounts.runtime.push(panel);
        break;
      case "app:framework":
        if (frameworks.some((p) => p.enabled && p.module === panel.module))
          mounts.framework.push(panel);
        break;
      case "app:container":
      case "app:deployment":
      case "app:tab":
        mounts.tabs.push(panel);
        break;
    }
    seen.add(key);
  }
  return mounts;
}
