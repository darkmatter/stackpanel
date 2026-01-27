"use client";

/**
 * Panels Panel
 *
 * Unified panels screen showing ALL module panels: status panels, info panels,
 * AND per-app configuration panels (PANEL_TYPE_APP_CONFIG). Modules are listed
 * in a left subnav. The content area shows status panels followed by per-app
 * config forms grouped by app.
 */

import { useMemo, useState } from "react";
import { Badge } from "@ui/badge";
import {
  Activity,
  ChevronDown,
  ChevronRight,
  Loader2,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useNixConfig } from "@/lib/use-agent";
import { useModules } from "./modules/use-modules";
import { PanelHeader } from "./shared/panel-header";
import {
  type AppModulePanel,
  type ModuleMeta,
  type NixPanel,
  getModuleIconById,
  formatModuleName,
  PanelRenderer,
  AppConfigFormRenderer,
} from "./shared";
import { useLocation } from "@tanstack/react-router";

// =============================================================================
// Types
// =============================================================================

interface PanelsByModule {
  /** Status/info/form panels (non-APP_CONFIG) */
  infoPanels: NixPanel[];
  /** Per-app config panels */
  appConfigPanels: AppModulePanel[];
}

// =============================================================================
// Hook: extract ALL panels from nix config, grouped by module
// =============================================================================

export function useAllPanelsGroupedByModule() {
  const { data: nixConfig, isLoading: configLoading } = useNixConfig();
  const {
    data: modulesData,
    isLoading: modulesLoading,
  } = useModules({ includeHealth: false, includeDisabled: false });

  const result = useMemo(() => {
    const cfg = nixConfig as Record<string, unknown> | null | undefined;
    if (!cfg)
      return {
        modules: [] as ModuleMeta[],
        byModule: {} as Record<string, PanelsByModule>,
        appIds: [] as string[],
      };

    // Try flake eval path first, then CLI config path
    const rawPanels =
      cfg.panelsComputed ??
      (cfg.ui as Record<string, unknown> | undefined)?.panels;
    if (!rawPanels || typeof rawPanels !== "object")
      return {
        modules: [] as ModuleMeta[],
        byModule: {} as Record<string, PanelsByModule>,
        appIds: [] as string[],
      };

    const panels = Object.values(rawPanels as Record<string, NixPanel>);
    const enabledPanels = panels
      .filter((p) => p.enabled)
      .sort((a, b) => a.order - b.order);

    // Group by module, separating info panels from app config panels
    const byModule: Record<string, PanelsByModule> = {};
    const allAppIds = new Set<string>();

    for (const panel of enabledPanels) {
      if (!byModule[panel.module]) {
        byModule[panel.module] = { infoPanels: [], appConfigPanels: [] };
      }

      if (panel.type === "PANEL_TYPE_APP_CONFIG") {
        byModule[panel.module].appConfigPanels.push(panel as AppModulePanel);
        // Collect all app IDs from the panel's apps map
        for (const appId of Object.keys(panel.apps)) {
          if (panel.apps[appId]?.enabled) {
            allAppIds.add(appId);
          }
        }
      } else {
        byModule[panel.module].infoPanels.push(panel);
      }
    }

    // Build module metadata list
    const moduleMap = new Map(
      modulesData?.modules?.map((m) => [m.id, m]) ?? [],
    );

    const moduleIds = Object.keys(byModule).sort((a, b) => {
      // Sort modules: those with info panels first, then by first panel order
      const aInfo = byModule[a]?.infoPanels?.[0]?.order ?? 999;
      const bInfo = byModule[b]?.infoPanels?.[0]?.order ?? 999;
      const aApp = byModule[a]?.appConfigPanels?.[0]?.fields?.[0] ? 500 : 999;
      const bApp = byModule[b]?.appConfigPanels?.[0]?.fields?.[0] ? 500 : 999;
      return Math.min(aInfo, aApp) - Math.min(bInfo, bApp);
    });

    const modules: ModuleMeta[] = moduleIds.map((id) => ({
      id,
      name: moduleMap.get(id)?.meta?.name ?? formatModuleName(id),
      icon: moduleMap.get(id)?.meta?.icon ?? null,
      description: moduleMap.get(id)?.meta?.description ?? null,
    }));

    // Sort app IDs alphabetically
    const appIds = Array.from(allAppIds).sort();

    return { modules, byModule, appIds };
  }, [nixConfig, modulesData]);

  return {
    ...result,
    isLoading: configLoading || modulesLoading,
  };
}

// =============================================================================
// Per-App Config Section
// =============================================================================

function AppConfigSection({
  appId,
  panels,
}: {
  appId: string;
  panels: AppModulePanel[];
}) {
  const [expanded, setExpanded] = useState(true);

  // Only show panels where this app is enabled
  const relevantPanels = panels.filter((p) => p.apps[appId]?.enabled);
  if (relevantPanels.length === 0) return null;

  return (
    <div className="rounded-lg border bg-card">
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-2 px-4 py-2.5 text-left hover:bg-muted/30 transition-colors"
      >
        {expanded ? (
          <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" />
        ) : (
          <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
        )}
        <span className="text-sm font-medium">{appId}</span>
        <Badge variant="secondary" className="text-[10px] px-1.5 py-0 ml-auto">
          {relevantPanels.reduce((n, p) => n + p.fields.length, 0)} fields
        </Badge>
      </button>

      {expanded && (
        <div className="px-4 pb-4 space-y-4 border-t">
          {relevantPanels.map((panel) => (
            <div key={panel.id} className="pt-3">
              <AppConfigFormRenderer
                panel={panel}
                appId={appId}
              />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Main Component
// =============================================================================

export function PanelsPanel() {
  const { modules, byModule, appIds, isLoading } =
    useAllPanelsGroupedByModule();
  const location = useLocation();
  const search = location.search;
  const activeModuleId = search
    ? new URLSearchParams(search).get("module")
    : null;
  // const [selectedModule, setSelectedModule] = useState<string | null>(null);

  const activeModule = activeModuleId ?? modules[0]?.id ?? null;
  const activeData = activeModule ? byModule[activeModule] : null;
  const activeModuleMeta = modules.find((m) => m.id === activeModule);

  if (isLoading) {
    return (
      <div className="flex min-h-[400px] items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (modules.length === 0) {
    return (
      <div className="space-y-6">
        <PanelHeader
          title="Panels"
          description="Module status and configuration panels"
        />
        <div className="flex min-h-[200px] flex-col items-center justify-center gap-3 text-center">
          <Activity className="h-12 w-12 text-muted-foreground/50" />
          <p className="text-sm text-muted-foreground">
            No module panels available. Enable modules in your Nix config to see
            their status and configuration here.
          </p>
        </div>
      </div>
    );
  }

  // Count total panels per module for the badge
  const panelCount = (moduleId: string) => {
    const data = byModule[moduleId];
    if (!data) return 0;
    return data.infoPanels.length + data.appConfigPanels.length;
  };

  // Collect app IDs that have config for the active module
  const activeAppIds = activeData
    ? appIds.filter((appId) =>
      activeData.appConfigPanels.some((p) => p.apps[appId]?.enabled),
    )
    : [];

  return (
    <div className="space-y-6">
      <PanelHeader
        title="Panels"
        description="Module status and configuration panels"
      />

      <div className="flex gap-6">
        {/* Subnav */}
        {/* <nav className="w-48 shrink-0 space-y-1">
          {modules.map((mod) => {
            const isActive = mod.id === activeModule;
            const Icon = getModuleIconById(mod.id);
            const count = panelCount(mod.id);
            const hasAppConfig = (byModule[mod.id]?.appConfigPanels.length ?? 0) > 0;

            return (
              <button
                key={mod.id}
                type="button"
                onClick={() => setSelectedModule(mod.id)}
                className={cn(
                  "w-full flex items-center gap-2 rounded-md px-3 py-2 text-sm transition-colors text-left",
                  isActive
                    ? "bg-primary/10 text-primary font-medium"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted/50",
                )}
              >
                <Icon className="h-4 w-4 shrink-0" />
                <span className="truncate flex-1">{mod.name}</span>
                <div className="flex items-center gap-1 ml-auto">
                  {hasAppConfig && (
                    <div
                      className="h-1.5 w-1.5 rounded-full bg-blue-400"
                      title="Has app configuration"
                    />
                  )}
                  <Badge
                    variant="secondary"
                    className="text-[10px] px-1.5 py-0"
                  >
                    {count}
                  </Badge>
                </div>
              </button>
            );
          })}
        </nav> */}

        {/* Panel content */}
        <div className="flex-1 min-w-0 space-y-6">
          {activeModuleMeta && (
            <div>
              <h3 className="text-lg font-semibold">{activeModuleMeta.name}</h3>
              {activeModuleMeta.description && (
                <p className="text-sm text-muted-foreground">
                  {activeModuleMeta.description}
                </p>
              )}
            </div>
          )}

          {/* Status / info panels */}
          {activeData && activeData.infoPanels.length > 0 && (
            <div className="space-y-4">
              {activeData.infoPanels.map((panel) => (
                <PanelRenderer key={panel.id} panel={panel} />
              ))}
            </div>
          )}

          {/* App configuration panels */}
          {activeData && activeData.appConfigPanels.length > 0 && (
            <div className="space-y-4">
              <div className="flex items-center gap-2">
                <h4 className="text-sm font-semibold text-foreground">
                  App Configuration
                </h4>
                <Badge variant="outline" className="text-[10px] px-1.5 py-0">
                  {activeAppIds.length} app{activeAppIds.length !== 1 ? "s" : ""}
                </Badge>
              </div>

              {activeAppIds.length === 0 ? (
                <p className="text-xs text-muted-foreground">
                  No apps have this module enabled.
                </p>
              ) : (
                <div className="space-y-3">
                  {activeAppIds.map((appId) => (
                    <AppConfigSection
                      key={appId}
                      appId={appId}
                      panels={activeData.appConfigPanels}
                    />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Empty state for module with no panels */}
          {activeData &&
            activeData.infoPanels.length === 0 &&
            activeData.appConfigPanels.length === 0 && (
              <p className="text-sm text-muted-foreground">
                No panels for this module.
              </p>
            )}
        </div>
      </div>
    </div>
  );
}
