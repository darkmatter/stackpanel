import { createContext, useContext, useMemo, type ReactNode } from "react";
import { useNixConfigQuery } from "@/lib/use-agent";
import { isJsonObject } from "./panel-data";
import type { NixPanel } from "./panel-types";

interface StudioModule {
  id: string;
  name: string;
  icon: string | null;
  description: string | null;
  readme: string | null;
  actionIds: string[];
}

export function studioPanelKey(panel: Pick<NixPanel, "module" | "id">) {
  return `panel:${JSON.stringify([panel.module, panel.id])}`;
}

export function studioPanelMatchesApp(panel: NixPanel, appId: string) {
  const apps = panel.apps;
  // A non-config panel can apply to every app. An app-config form always
  // needs an enabled record for the app whose settings it would write.
  return (
    apps[appId]?.enabled === true ||
    (panel.type !== "PANEL_TYPE_APP_CONFIG" && Object.keys(apps).length === 0)
  );
}

interface StudioCatalog {
  modules: Map<string, StudioModule>;
  catalog: NixPanel[];
  panels: NixPanel[];
}

function getStudioCatalog(config: Record<string, unknown>): StudioCatalog {
  if (!Array.isArray(config.modulesListAll) || !Array.isArray(config.panelsList))
    throw new Error("The project snapshot is missing its evaluated modules or panels.");
  const modules = new Map<string, StudioModule>();
  for (const mod of config.modulesListAll as unknown[]) {
    if (!isJsonObject(mod) || typeof mod.id !== "string" || typeof mod.enabled !== "boolean")
      throw new Error("Invalid module identity in the evaluated snapshot.");
    if (!mod.enabled) continue;
    if (!isJsonObject(mod.meta) || typeof mod.meta.name !== "string" || !isJsonObject(mod.actions))
      throw new Error(`Missing metadata for evaluated module ${mod.id}.`);
    modules.set(mod.id, {
      id: mod.id,
      name: mod.meta.name,
      icon: typeof mod.meta.icon === "string" ? mod.meta.icon : null,
      description: typeof mod.meta.description === "string" ? mod.meta.description : null,
      readme: typeof mod.readme === "string" ? mod.readme : null,
      actionIds: Object.keys(mod.actions),
    });
  }
  const evaluated = config.panelsList as NixPanel[];
  for (const panel of evaluated) {
    if (
      !panel ||
      !panel.id ||
      !panel.module ||
      typeof panel.enabled !== "boolean" ||
      !panel.slot ||
      !panel.type ||
      (panel.slot === "sidebar" && !panel.nav?.section) ||
      typeof panel.title !== "string" ||
      !Number.isFinite(panel.order) ||
      !Array.isArray(panel.fields) ||
      !isJsonObject(panel.apps) ||
      !Object.values(panel.apps).every(
        (app) => app && typeof app.enabled === "boolean" && isJsonObject(app.config),
      )
    )
      throw new Error("The project snapshot contains an incomplete panel descriptor.");
  }
  const catalog = evaluated
    .filter((panel) => panel.enabled && modules.has(panel.module))
    .sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
  return { modules, catalog, panels: getRootStudioPanels(catalog) };
}

export function getRootStudioPanels(catalog: readonly NixPanel[]) {
  // Tab IDs are local references, not permission to re-mount another slot
  // or another module's panels. Keep children in the renderer's catalog.
  const children = new Set<string>();
  for (const panel of catalog) {
    if (panel.type !== "PANEL_TYPE_TABS") continue;
    for (const id of panel.tabs ?? []) {
      if (id !== panel.id) children.add(JSON.stringify([panel.module, panel.slot, id]));
    }
  }
  return catalog.filter(
    (panel) => !children.has(JSON.stringify([panel.module, panel.slot, panel.id])),
  );
}

interface StudioPanels extends StudioCatalog {
  config: Record<string, unknown> | null;
  isLoading: boolean;
  error: Error | null;
}
const PanelContext = createContext<StudioPanels | null>(null);
const emptyCatalog: StudioCatalog = { modules: new Map(), panels: [], catalog: [] };

export function StudioPanelsProvider({ children }: { children: ReactNode }) {
  const { data, isLoading, error } = useNixConfigQuery();
  const config = data?.config ?? null;
  const value = useMemo<StudioPanels>(() => {
    if (!data || error) return { ...emptyCatalog, config: null, isLoading, error };
    try {
      if (!config) throw new Error("No evaluated project snapshot was returned.");
      return { ...getStudioCatalog(config), config, isLoading, error: null };
    } catch (cause) {
      return {
        ...emptyCatalog,
        config: null,
        isLoading,
        error: cause instanceof Error ? cause : new Error(String(cause)),
      };
    }
  }, [data, config, isLoading, error]);
  return <PanelContext.Provider value={value}>{children}</PanelContext.Provider>;
}

export function useStudioPanels() {
  const value = useContext(PanelContext);
  if (!value) throw new Error("Studio panels require a project-scoped StudioPanelsProvider");
  return value;
}
