/**
 * Modules Panel
 *
 * Main panel for the Module Browser. Shows a list of all stackpanel modules
 * with filtering, search, and enable/disable capabilities.
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@ui/collapsible";
import { Input } from "@ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import {
  AlertCircle,
  Check,
  CheckCircle,
  ChevronDown,
  ChevronRight,
  Cloud,
  Code,
  Database,
  ExternalLink,
  FileCode,
  FolderGit,
  Heart,
  Key,
  Loader2,
  Package,
  Puzzle,
  RefreshCw,
  Search,
  Settings,
  Terminal,
  XCircle,
} from "lucide-react";
import { useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import { PanelHeader } from "../shared/panel-header";
import { useModules, useEnableModule } from "./use-modules";
import { ModuleDetailDrawer } from "./module-detail-drawer";
import { RegistryBrowser } from "./registry-browser";
import {
  type Module,
  type HealthStatus,
  MODULE_CATEGORIES,
  getCategoryLabel,
  getSourceLabel,
  getHealthStatusColor,
} from "./types";

// =============================================================================
// Health Status Icon
// =============================================================================

function HealthStatusIcon({
  status,
  className,
}: {
  status: HealthStatus;
  className?: string;
}) {
  const color = getHealthStatusColor(status);

  switch (status) {
    case "HEALTH_STATUS_HEALTHY":
      return <CheckCircle className={cn("h-4 w-4", color, className)} />;
    case "HEALTH_STATUS_DEGRADED":
      return <AlertCircle className={cn("h-4 w-4", color, className)} />;
    case "HEALTH_STATUS_UNHEALTHY":
      return <XCircle className={cn("h-4 w-4", color, className)} />;
    default:
      return <Heart className={cn("h-4 w-4", color, className)} />;
  }
}

// =============================================================================
// Feature Icons
// =============================================================================

function FeatureBadges({ features }: { features: Module["features"] }) {
  const featureList = [
    { key: "files", icon: FileCode, label: "Files" },
    { key: "scripts", icon: Terminal, label: "Scripts" },
    { key: "healthchecks", icon: Heart, label: "Health" },
    { key: "services", icon: Cloud, label: "Services" },
    { key: "secrets", icon: Key, label: "Secrets" },
    { key: "packages", icon: Package, label: "Packages" },
    { key: "appModule", icon: Code, label: "App Config" },
  ] as const;

  const activeFeatures = featureList.filter(
    (f) => features[f.key as keyof typeof features],
  );

  if (activeFeatures.length === 0) return null;

  return (
    <div className="flex flex-wrap gap-1">
      {activeFeatures.map(({ key, icon: Icon, label }) => (
        <Badge
          key={key}
          variant="outline"
          className="gap-1 px-1.5 py-0.5 text-xs"
        >
          <Icon className="h-3 w-3" />
          <span className="hidden sm:inline">{label}</span>
        </Badge>
      ))}
    </div>
  );
}

// =============================================================================
// Module Card
// =============================================================================

interface ModuleCardProps {
  module: Module;
  onSelect: (module: Module) => void;
}

function ModuleCard({ module, onSelect }: ModuleCardProps) {
  const [expanded, setExpanded] = useState(false);
  const enableMutation = useEnableModule(module.id);

  const handleToggleEnable = async (checked: boolean) => {
    await enableMutation.mutateAsync(checked);
  };

  const categoryIcon = useMemo(() => {
    switch (module.meta.category) {
      case "database":
        return Database;
      case "infrastructure":
        return Cloud;
      case "development":
        return Code;
      case "secrets":
        return Key;
      default:
        return Puzzle;
    }
  }, [module.meta.category]);

  const CategoryIcon = categoryIcon;

  return (
    <Collapsible open={expanded} onOpenChange={setExpanded}>
      <Card
        className={cn(
          "transition-all",
          !module.enabled && "opacity-60",
          module.health?.status === "HEALTH_STATUS_UNHEALTHY" &&
            "border-red-500/30",
          module.health?.status === "HEALTH_STATUS_DEGRADED" &&
            "border-yellow-500/30",
        )}
      >
        <CollapsibleTrigger asChild>
          <CardHeader className="cursor-pointer py-4 transition-colors hover:bg-muted/50">
            <div className="flex items-center justify-between gap-4">
              <div className="flex min-w-0 flex-1 items-center gap-3">
                {expanded ? (
                  <ChevronDown className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
                ) : (
                  <ChevronRight className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
                )}
                <CategoryIcon className="h-5 w-5 flex-shrink-0 text-muted-foreground" />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <CardTitle className="truncate text-base">
                      {module.meta.name}
                    </CardTitle>
                    {module.source.type === "builtin" && (
                      <Badge variant="secondary" className="text-xs">
                        Builtin
                      </Badge>
                    )}
                    {module.source.type === "flake-input" && (
                      <Badge
                        variant="outline"
                        className="gap-1 text-xs text-blue-500"
                      >
                        <FolderGit className="h-3 w-3" />
                        Flake
                      </Badge>
                    )}
                  </div>
                  {module.meta.description && (
                    <p className="truncate text-sm text-muted-foreground">
                      {module.meta.description}
                    </p>
                  )}
                </div>
              </div>

              <div className="flex items-center gap-3">
                {/* Health Status */}
                {module.health && (
                  <div className="flex items-center gap-1.5">
                    <HealthStatusIcon status={module.health.status} />
                    <span className="hidden text-xs text-muted-foreground sm:inline">
                      {module.health.healthyCount}/{module.health.totalCount}
                    </span>
                  </div>
                )}

                {/* Enable Toggle */}
                <Switch
                  checked={module.enabled}
                  onCheckedChange={handleToggleEnable}
                  disabled={enableMutation.isPending}
                  onClick={(e) => e.stopPropagation()}
                />
              </div>
            </div>
          </CardHeader>
        </CollapsibleTrigger>

        <CollapsibleContent>
          <CardContent className="border-t pt-4">
            <ModuleDetails
              module={module}
              onConfigure={() => onSelect(module)}
            />
          </CardContent>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}

// =============================================================================
// Module Details
// =============================================================================

function ModuleDetails({
  module,
  onConfigure,
}: {
  module: Module;
  onConfigure: () => void;
}) {
  return (
    <div className="space-y-4">
      {/* Features */}
      <div>
        <h4 className="mb-2 text-sm font-medium">Features</h4>
        <FeatureBadges features={module.features} />
        {Object.values(module.features).every((v) => !v) && (
          <p className="text-sm text-muted-foreground">No features declared</p>
        )}
      </div>

      {/* Health Summary */}
      {module.health && (
        <div>
          <h4 className="mb-2 text-sm font-medium">Health Checks</h4>
          <div className="space-y-1">
            {module.health.checks.map((check) => (
              <div
                key={check.checkId}
                className="flex items-center justify-between rounded-md border px-3 py-2 text-sm"
              >
                <div className="flex items-center gap-2">
                  <HealthStatusIcon status={check.status} />
                  <span>{check.check?.name ?? check.checkId}</span>
                </div>
                <span className="text-xs text-muted-foreground">
                  {check.durationMs}ms
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tags */}
      {module.tags && module.tags.length > 0 && (
        <div>
          <h4 className="mb-2 text-sm font-medium">Tags</h4>
          <div className="flex flex-wrap gap-1">
            {module.tags.map((tag) => (
              <Badge key={tag} variant="outline" className="text-xs">
                {tag}
              </Badge>
            ))}
          </div>
        </div>
      )}

      {/* Source Info */}
      <div className="grid gap-2 text-sm">
        <div className="flex items-center gap-2">
          <span className="text-muted-foreground">Source:</span>
          <Badge variant="outline">{getSourceLabel(module.source.type)}</Badge>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-muted-foreground">Category:</span>
          <span>{getCategoryLabel(module.meta.category)}</span>
        </div>
        {module.meta.version && (
          <div className="flex items-center gap-2">
            <span className="text-muted-foreground">Version:</span>
            <span>{module.meta.version}</span>
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="flex gap-2 pt-2">
        <Button variant="outline" size="sm" onClick={onConfigure}>
          <Settings className="mr-2 h-4 w-4" />
          Configure
        </Button>
        {module.meta.homepage && (
          <Button variant="ghost" size="sm" asChild>
            <a
              href={module.meta.homepage}
              target="_blank"
              rel="noopener noreferrer"
            >
              <ExternalLink className="mr-2 h-4 w-4" />
              Docs
            </a>
          </Button>
        )}
      </div>
    </div>
  );
}

// =============================================================================
// Stats Card
// =============================================================================

function StatsCard({
  total,
  enabled,
  healthySummary,
}: {
  total: number;
  enabled: number;
  healthySummary: { healthy: number; degraded: number; unhealthy: number };
}) {
  return (
    <Card className="py-4">
      <CardContent>
        <div className="flex flex-wrap items-center gap-4 text-sm sm:gap-6">
          <div className="flex items-center gap-2">
            <Package className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">{total}</span>
            <span className="text-muted-foreground">total</span>
          </div>
          <div className="h-4 w-px bg-border" />
          <div className="flex items-center gap-2">
            <Check className="h-4 w-4 text-green-500" />
            <span className="font-medium">{enabled}</span>
            <span className="text-muted-foreground">enabled</span>
          </div>
          {healthySummary.healthy > 0 && (
            <>
              <div className="h-4 w-px bg-border" />
              <div className="flex items-center gap-2">
                <CheckCircle className="h-4 w-4 text-green-500" />
                <span className="font-medium">{healthySummary.healthy}</span>
                <span className="text-muted-foreground">healthy</span>
              </div>
            </>
          )}
          {healthySummary.degraded > 0 && (
            <div className="flex items-center gap-2">
              <AlertCircle className="h-4 w-4 text-yellow-500" />
              <span className="font-medium">{healthySummary.degraded}</span>
              <span className="text-muted-foreground">degraded</span>
            </div>
          )}
          {healthySummary.unhealthy > 0 && (
            <div className="flex items-center gap-2">
              <XCircle className="h-4 w-4 text-red-500" />
              <span className="font-medium">{healthySummary.unhealthy}</span>
              <span className="text-muted-foreground">unhealthy</span>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

// =============================================================================
// Empty State
// =============================================================================

function EmptyState({ hasFilter }: { hasFilter: boolean }) {
  if (hasFilter) {
    return (
      <div className="flex min-h-[200px] flex-col items-center justify-center gap-4">
        <Search className="h-12 w-12 text-muted-foreground/50" />
        <div className="text-center">
          <h2 className="text-lg font-semibold">No matching modules</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Try adjusting your search or filters
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-[300px] flex-col items-center justify-center gap-4">
      <Puzzle className="h-16 w-16 text-muted-foreground/50" />
      <div className="text-center">
        <h2 className="text-xl font-semibold">No Modules Found</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Modules extend Stackpanel with additional functionality.
        </p>
        <p className="mt-4 text-xs text-muted-foreground">
          Enable modules in your Nix config or install from the module registry.
        </p>
      </div>
    </div>
  );
}

// =============================================================================
// Main Panel
// =============================================================================

export function ModulesPanel() {
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);
  const [showDisabled, setShowDisabled] = useState(true);
  const [selectedModuleId, setSelectedModuleId] = useState<string | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);

  const handleSelectModule = (module: Module) => {
    setSelectedModuleId(module.id);
    setDrawerOpen(true);
  };

  const { data, isLoading, isError, error, refetch } = useModules({
    includeHealth: true,
    includeDisabled: showDisabled,
  });

  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await refetch();
    } finally {
      setIsRefreshing(false);
    }
  };

  // Filter and sort modules
  const filteredModules = useMemo(() => {
    if (!data?.modules) return [];

    let modules = data.modules;

    // Text search
    if (search) {
      const searchLower = search.toLowerCase();
      modules = modules.filter(
        (m) =>
          m.id.toLowerCase().includes(searchLower) ||
          m.meta.name.toLowerCase().includes(searchLower) ||
          m.meta.description?.toLowerCase().includes(searchLower) ||
          m.tags?.some((t) => t.toLowerCase().includes(searchLower)),
      );
    }

    // Category filter
    if (categoryFilter) {
      modules = modules.filter((m) => m.meta.category === categoryFilter);
    }

    // Sort by priority, then by name
    return modules.sort((a, b) => {
      if (a.priority !== b.priority) return a.priority - b.priority;
      return a.meta.name.localeCompare(b.meta.name);
    });
  }, [data?.modules, search, categoryFilter]);

  // Health summary
  const healthSummary = useMemo(() => {
    const summary = { healthy: 0, degraded: 0, unhealthy: 0 };
    data?.modules?.forEach((m) => {
      if (!m.health) return;
      if (m.health.status === "HEALTH_STATUS_HEALTHY") summary.healthy++;
      else if (m.health.status === "HEALTH_STATUS_DEGRADED") summary.degraded++;
      else if (m.health.status === "HEALTH_STATUS_UNHEALTHY")
        summary.unhealthy++;
    });
    return summary;
  }, [data?.modules]);

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
            Failed to load modules: {error?.message || "Unknown error"}
          </p>
        </div>
        <Button variant="outline" onClick={handleRefresh}>
          Try again
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PanelHeader
        title="Modules"
        description="Extend Stackpanel with built-in and community modules"
      />

      <Tabs defaultValue="registry" className="w-full">
        <TabsList className="grid w-full grid-cols-2 sm:w-[400px]">
          <TabsTrigger value="registry" className="gap-2">
            <Package className="h-4 w-4" />
            Browse Modules
          </TabsTrigger>
          <TabsTrigger value="installed" className="gap-2">
            <Check className="h-4 w-4" />
            Installed
            {(data?.enabled ?? 0) > 0 && (
              <Badge variant="secondary" className="ml-1">
                {data?.enabled ?? 0}
              </Badge>
            )}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="registry" className="mt-6">
          <RegistryBrowser />
        </TabsContent>

        <TabsContent value="installed" className="mt-6 space-y-6">
          {/* Stats */}
          <div className="flex items-center justify-between">
            <StatsCard
              total={data?.total ?? 0}
              enabled={data?.enabled ?? 0}
              healthySummary={healthSummary}
            />
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

          {/* Filters */}
          <div className="flex flex-col gap-3 sm:flex-row">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                placeholder="Search modules..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="pl-10"
              />
            </div>
            <Select
              value={categoryFilter ?? "all"}
              onValueChange={(v) => setCategoryFilter(v === "all" ? null : v)}
            >
              <SelectTrigger className="w-full sm:w-[180px]">
                <SelectValue placeholder="All categories" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All categories</SelectItem>
                {MODULE_CATEGORIES.map((cat) => (
                  <SelectItem key={cat.value} value={cat.value}>
                    {cat.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="flex items-center gap-2">
              <Switch
                id="show-disabled"
                checked={showDisabled}
                onCheckedChange={setShowDisabled}
              />
              <label htmlFor="show-disabled" className="text-sm">
                Show disabled
              </label>
            </div>
          </div>

          {/* Module List */}
          {filteredModules.length === 0 ? (
            <EmptyState hasFilter={!!search || !!categoryFilter} />
          ) : (
            <div className="space-y-3">
              {filteredModules.map((module) => (
                <ModuleCard
                  key={module.id}
                  module={module}
                  onSelect={handleSelectModule}
                />
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>

      {/* Module Detail Drawer */}
      <ModuleDetailDrawer
        moduleId={selectedModuleId}
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
      />
    </div>
  );
}
