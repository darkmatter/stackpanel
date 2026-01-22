/**
 * Dashboard Page
 *
 * Displays core module panels (Go, Caddy, Healthchecks, etc.)
 * These are NOT extensions - they're built-in modules with UI panels.
 *
 * Extensions (like SST) are shown on the /studio/extensions page.
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@ui/collapsible";
import { createFileRoute } from "@tanstack/react-router";
import {
  Activity,
  AlertCircle,
  Boxes,
  CheckCircle,
  ChevronDown,
  ChevronRight,
  Code,
  Gauge,
  LayoutDashboard,
  Loader2,
  Network,
  RefreshCw,
  Server,
  XCircle,
} from "lucide-react";
import { useState } from "react";
import { useNixConfig } from "@/lib/use-agent";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/studio/dashboard")({
  component: DashboardPage,
});

// =============================================================================
// Types
// =============================================================================

interface PanelField {
  name: string;
  type: string;
  value: string;
  options?: string[];
}

interface PanelAppData {
  enabled: boolean;
  config: Record<string, string>;
}

interface ModulePanel {
  id: string;
  module: string;
  title: string;
  description?: string | null;
  icon?: string | null;
  type: string;
  order: number;
  enabled: boolean;
  fields: PanelField[];
  apps: Record<string, PanelAppData>;
}

interface StatusMetric {
  label: string;
  value: string | number;
  status?: "ok" | "warning" | "error";
}

// Icon mapping
const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  code: Code,
  server: Server,
  network: Network,
  activity: Activity,
  boxes: Boxes,
  gauge: Gauge,
};

// =============================================================================
// Main Component
// =============================================================================

function DashboardPage() {
  const { data: config, isLoading, isError, error, refetch } = useNixConfig();
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [expandedModules, setExpandedModules] = useState<Set<string>>(
    new Set(["healthchecks", "go", "caddy"]),
  );

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await refetch();
    } finally {
      setIsRefreshing(false);
    }
  };

  const toggleModule = (module: string) => {
    setExpandedModules((prev) => {
      const next = new Set(prev);
      if (next.has(module)) {
        next.delete(module);
      } else {
        next.add(module);
      }
      return next;
    });
  };

  if (isLoading) {
    return (
      <div className="flex min-h-[400px] items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex min-h-[400px] flex-col items-center justify-center gap-4">
        <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
          <p className="text-sm text-destructive">
            Failed to load dashboard: {error?.message || "Unknown error"}
          </p>
        </div>
        <Button variant="outline" onClick={handleRefresh}>
          Try again
        </Button>
      </div>
    );
  }

  // Extract panels from config
  const configRecord = config as Record<string, unknown> | undefined;
  const panels = configRecord?.panels as Record<string, ModulePanel> | undefined;
  const panelModules = configRecord?.panelModules as string[] | undefined;
  const projectName = (configRecord?.name as string) || "Stackpanel";

  // Group panels by module
  const panelsByModule: Record<string, ModulePanel[]> = {};
  if (panels) {
    for (const [id, panel] of Object.entries(panels)) {
      if (!panel.enabled) continue;
      if (!panelsByModule[panel.module]) {
        panelsByModule[panel.module] = [];
      }
      panelsByModule[panel.module].push({ ...panel, id });
    }
    // Sort panels within each module by order
    for (const module of Object.keys(panelsByModule)) {
      panelsByModule[module].sort((a, b) => a.order - b.order);
    }
  }

  const moduleCount = panelModules?.length || Object.keys(panelsByModule).length;
  const panelCount = panels ? Object.keys(panels).length : 0;

  return (
    <div className="container mx-auto space-y-6 py-8">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <h1 className="flex items-center gap-2 text-3xl font-bold">
            <LayoutDashboard className="h-8 w-8" />
            Dashboard
          </h1>
          <p className="text-muted-foreground">
            System status and module panels for {projectName}
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={handleRefresh}
          disabled={isRefreshing}
        >
          <RefreshCw
            className={cn("mr-2 h-4 w-4", isRefreshing && "animate-spin")}
          />
          {isRefreshing ? "Refreshing..." : "Refresh"}
        </Button>
      </div>

      {/* Summary Card */}
      <Card>
        <CardContent className="py-4">
          <div className="flex items-center gap-6 text-sm">
            <div className="flex items-center gap-2">
              <Boxes className="h-4 w-4 text-muted-foreground" />
              <span className="font-medium">{moduleCount}</span>
              <span className="text-muted-foreground">active modules</span>
            </div>
            <div className="h-4 w-px bg-border" />
            <div className="flex items-center gap-2">
              <Gauge className="h-4 w-4 text-blue-500" />
              <span className="font-medium">{panelCount}</span>
              <span className="text-muted-foreground">panels</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Module Panels */}
      {moduleCount === 0 ? (
        <EmptyState />
      ) : (
        <div className="space-y-4">
          {(panelModules || Object.keys(panelsByModule)).map((module) => {
            const modulePanels = panelsByModule[module] || [];
            if (modulePanels.length === 0) return null;

            return (
              <ModuleSection
                key={module}
                module={module}
                panels={modulePanels}
                expanded={expandedModules.has(module)}
                onToggle={() => toggleModule(module)}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Module Section Component
// =============================================================================

function ModuleSection({
  module,
  panels,
  expanded,
  onToggle,
}: {
  module: string;
  panels: ModulePanel[];
  expanded: boolean;
  onToggle: () => void;
}) {
  // Get the first panel's icon for the module header
  const firstPanel = panels[0];
  const IconComponent = firstPanel?.icon
    ? iconMap[firstPanel.icon] || Boxes
    : Boxes;

  // Format module name for display
  const displayName = module.charAt(0).toUpperCase() + module.slice(1);

  return (
    <Collapsible open={expanded} onOpenChange={onToggle}>
      <Card>
        <CollapsibleTrigger asChild>
          <CardHeader className="cursor-pointer hover:bg-muted/50 transition-colors py-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                {expanded ? (
                  <ChevronDown className="h-4 w-4 text-muted-foreground" />
                ) : (
                  <ChevronRight className="h-4 w-4 text-muted-foreground" />
                )}
                <IconComponent className="h-5 w-5 text-primary" />
                <CardTitle className="text-lg">{displayName}</CardTitle>
                <Badge variant="secondary" className="text-xs">
                  {panels.length} panel{panels.length !== 1 ? "s" : ""}
                </Badge>
              </div>
            </div>
          </CardHeader>
        </CollapsibleTrigger>

        <CollapsibleContent>
          <CardContent className="border-t pt-4 space-y-4">
            {panels.map((panel) => (
              <PanelRenderer key={panel.id} panel={panel} />
            ))}
          </CardContent>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}

// =============================================================================
// Panel Renderer Component
// =============================================================================

function PanelRenderer({ panel }: { panel: ModulePanel }) {
  switch (panel.type) {
    case "PANEL_TYPE_STATUS":
      return <StatusPanelContent panel={panel} />;
    case "PANEL_TYPE_APPS_GRID":
      return <AppsGridPanelContent panel={panel} />;
    default:
      return (
        <div className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
          Unknown panel type: {panel.type}
        </div>
      );
  }
}

// =============================================================================
// Status Panel Content
// =============================================================================

function StatusPanelContent({ panel }: { panel: ModulePanel }) {
  // Find the metrics field
  const metricsField = panel.fields.find((f) => f.name === "metrics");
  let metrics: StatusMetric[] = [];

  if (metricsField?.value) {
    try {
      metrics = JSON.parse(metricsField.value);
    } catch {
      // Invalid JSON, leave empty
    }
  }

  if (metrics.length === 0) {
    return (
      <div className="rounded-lg border p-4">
        <h4 className="font-medium mb-2">{panel.title}</h4>
        <p className="text-sm text-muted-foreground">No metrics available</p>
      </div>
    );
  }

  return (
    <div className="rounded-lg border p-4">
      <h4 className="font-medium mb-3">{panel.title}</h4>
      {panel.description && (
        <p className="text-sm text-muted-foreground mb-3">{panel.description}</p>
      )}
      <div className="grid gap-3 sm:grid-cols-2">
        {metrics.map((metric, index) => (
          <MetricItem key={`${metric.label}-${index}`} metric={metric} />
        ))}
      </div>
    </div>
  );
}

function MetricItem({ metric }: { metric: StatusMetric }) {
  const status = metric.status || "ok";
  const StatusIcon =
    status === "ok"
      ? CheckCircle
      : status === "warning"
        ? AlertCircle
        : XCircle;
  const statusColor =
    status === "ok"
      ? "text-green-500"
      : status === "warning"
        ? "text-yellow-500"
        : "text-red-500";

  return (
    <div className="flex items-center gap-3 rounded-md bg-muted/30 p-2">
      <StatusIcon className={cn("h-4 w-4 flex-shrink-0", statusColor)} />
      <div className="flex min-w-0 flex-1 items-baseline justify-between gap-2">
        <span className="truncate text-sm text-muted-foreground">
          {metric.label}
        </span>
        <span className="font-medium text-sm">{metric.value}</span>
      </div>
    </div>
  );
}

// =============================================================================
// Apps Grid Panel Content
// =============================================================================

function AppsGridPanelContent({ panel }: { panel: ModulePanel }) {
  // Find the columns field
  const columnsField = panel.fields.find((f) => f.name === "columns");
  let columns: string[] = ["name"];

  if (columnsField?.value) {
    try {
      columns = JSON.parse(columnsField.value);
    } catch {
      // Invalid JSON, use default
    }
  }

  // Get apps from panel
  const apps = Object.entries(panel.apps).filter(([_, data]) => data.enabled);

  if (apps.length === 0) {
    return (
      <div className="rounded-lg border p-4">
        <h4 className="font-medium mb-2">{panel.title}</h4>
        <p className="text-sm text-muted-foreground">No apps configured</p>
      </div>
    );
  }

  return (
    <div className="rounded-lg border p-4">
      <div className="flex items-center justify-between mb-3">
        <h4 className="font-medium">{panel.title}</h4>
        <Badge variant="secondary">{apps.length}</Badge>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {apps.map(([name, data]) => (
          <AppCard key={name} name={name} config={data.config} columns={columns} />
        ))}
      </div>
    </div>
  );
}

function AppCard({
  name,
  config,
  columns,
}: {
  name: string;
  config: Record<string, string>;
  columns: string[];
}) {
  return (
    <div className="rounded-lg border bg-card p-3 transition-colors hover:bg-muted/50">
      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <h5 className="font-medium">{name}</h5>
          {columns.includes("path") && config.path && (
            <p className="text-xs text-muted-foreground truncate max-w-[180px]">
              {config.path}
            </p>
          )}
        </div>
        <div className="flex items-center gap-1">
          {columns.includes("version") && config.version && (
            <Badge variant="outline" className="text-xs">
              v{config.version}
            </Badge>
          )}
          {columns.includes("port") && config.port && (
            <Badge variant="secondary" className="text-xs">
              :{config.port}
            </Badge>
          )}
        </div>
      </div>
      {/* Additional config display */}
      {Object.entries(config).some(
        ([key]) => !["path", "version", "port", "name"].includes(key),
      ) && (
        <div className="mt-2 flex flex-wrap gap-1">
          {Object.entries(config)
            .filter(([key]) => !["path", "version", "port", "name"].includes(key))
            .slice(0, 2)
            .map(([key, value]) => (
              <Badge key={key} variant="outline" className="text-xs">
                {key}: {value}
              </Badge>
            ))}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Empty State
// =============================================================================

function EmptyState() {
  return (
    <div className="flex min-h-[300px] flex-col items-center justify-center gap-4">
      <LayoutDashboard className="h-16 w-16 text-muted-foreground/50" />
      <div className="text-center">
        <h2 className="text-xl font-semibold">No Module Panels</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Enable modules like Go, Caddy, or Healthchecks to see their status
          here.
        </p>
      </div>
    </div>
  );
}
