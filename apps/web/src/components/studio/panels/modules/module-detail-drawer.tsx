/**
 * Module Detail Drawer
 *
 * A slide-out panel that shows detailed information about a module,
 * including its configuration, health status, and metadata.
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@ui/sheet";
import { Switch } from "@ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { Link } from "@tanstack/react-router";
import {
  AlertCircle,
  Check,
  CheckCircle,
  Clock,
  Cloud,
  Code,
  ExternalLink,
  FileCode,
  FolderGit,
  Heart,
  Key,
  Loader2,
  Package,
  RefreshCw,
  Search,
  Settings,
  Terminal,
  XCircle,
} from "lucide-react";
import { cn } from "@/lib/utils";
import {
  useModule,
  useEnableModule,
  useRunModuleHealthchecks,
} from "./use-modules";
import { ModuleConfigForm } from "./module-config-form";
import {
  type Module,
  type HealthStatus,
  type HealthcheckResult,
  getCategoryLabel,
  getSourceLabel,
  getHealthStatusColor,
  getHealthStatusLabel,
} from "./types";

// =============================================================================
// Props
// =============================================================================

interface ModuleDetailDrawerProps {
  moduleId: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

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
// Feature Grid
// =============================================================================

function FeatureGrid({ features }: { features: Module["features"] }) {
  const featureList = [
    { key: "files", icon: FileCode, label: "Files" },
    { key: "scripts", icon: Terminal, label: "Scripts" },
    { key: "healthchecks", icon: Heart, label: "Health Checks" },
    { key: "services", icon: Cloud, label: "Services" },
    { key: "secrets", icon: Key, label: "Secrets" },
    { key: "packages", icon: Package, label: "Packages" },
    { key: "tasks", icon: Code, label: "Tasks" },
    { key: "appModule", icon: Settings, label: "App Config" },
  ] as const;

  return (
    <div className="grid grid-cols-2 gap-2">
      {featureList.map(({ key, icon: Icon, label }) => {
        const enabled = features[key as keyof typeof features];
        return (
          <div
            key={key}
            className={cn(
              "flex items-center gap-2 rounded-md border px-3 py-2 text-sm",
              enabled
                ? "border-green-500/30 bg-green-500/5"
                : "border-muted bg-muted/30 opacity-50",
            )}
          >
            {enabled ? (
              <Check className="h-3.5 w-3.5 text-green-500" />
            ) : (
              <XCircle className="h-3.5 w-3.5 text-muted-foreground" />
            )}
            <Icon className="h-3.5 w-3.5" />
            <span>{label}</span>
          </div>
        );
      })}
    </div>
  );
}

// =============================================================================
// Overview Tab
// =============================================================================

function OverviewTab({ module }: { module: Module }) {
  return (
    <div className="space-y-6">
      {/* Description */}
      {module.meta.description && (
        <div>
          <h4 className="mb-2 text-sm font-medium">Description</h4>
          <p className="text-sm text-muted-foreground">
            {module.meta.description}
          </p>
        </div>
      )}

      {/* Features */}
      <div>
        <h4 className="mb-2 text-sm font-medium">Features</h4>
        <FeatureGrid features={module.features} />
      </div>

      {/* Metadata */}
      <div>
        <h4 className="mb-2 text-sm font-medium">Details</h4>
        <div className="space-y-2 text-sm">
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground">Category</span>
            <span>{getCategoryLabel(module.meta.category)}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground">Source</span>
            <Badge variant="outline">
              {getSourceLabel(module.source.type)}
            </Badge>
          </div>
          {module.meta.version && (
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Version</span>
              <span>{module.meta.version}</span>
            </div>
          )}
          {module.meta.author && (
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Author</span>
              <span>{module.meta.author}</span>
            </div>
          )}
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground">Priority</span>
            <span>{module.priority}</span>
          </div>
        </div>
      </div>

      {/* Source Info */}
      {module.source.type !== "builtin" && (
        <div>
          <h4 className="mb-2 text-sm font-medium">Source</h4>
          <div className="rounded-md border bg-muted/30 p-3 text-sm">
            {module.source.flakeInput && (
              <div className="flex items-center gap-2">
                <FolderGit className="h-4 w-4 text-muted-foreground" />
                <code className="text-xs">{module.source.flakeInput}</code>
              </div>
            )}
            {module.source.path && (
              <div className="mt-1 text-xs text-muted-foreground">
                Path: {module.source.path}
              </div>
            )}
            {module.source.ref && (
              <div className="mt-1 text-xs text-muted-foreground">
                Ref: {module.source.ref}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Tags */}
      {module.tags && module.tags.length > 0 && (
        <div>
          <h4 className="mb-2 text-sm font-medium">Tags</h4>
          <div className="flex flex-wrap gap-1">
            {module.tags.map((tag) => (
              <Badge key={tag} variant="secondary" className="text-xs">
                {tag}
              </Badge>
            ))}
          </div>
        </div>
      )}

      {/* Dependencies */}
      {(module.requires?.length || module.conflicts?.length) && (
        <div>
          <h4 className="mb-2 text-sm font-medium">Dependencies</h4>
          {module.requires && module.requires.length > 0 && (
            <div className="mb-2">
              <span className="text-xs text-muted-foreground">Requires:</span>
              <div className="mt-1 flex flex-wrap gap-1">
                {module.requires.map((req) => (
                  <Badge key={req} variant="outline" className="text-xs">
                    {req}
                  </Badge>
                ))}
              </div>
            </div>
          )}
          {module.conflicts && module.conflicts.length > 0 && (
            <div>
              <span className="text-xs text-muted-foreground">
                Conflicts with:
              </span>
              <div className="mt-1 flex flex-wrap gap-1">
                {module.conflicts.map((conflict) => (
                  <Badge
                    key={conflict}
                    variant="destructive"
                    className="text-xs"
                  >
                    {conflict}
                  </Badge>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Links */}
      <div className="flex flex-wrap gap-2">
        {module.meta.homepage && (
          <Button variant="outline" size="sm" asChild>
            <a
              href={module.meta.homepage}
              target="_blank"
              rel="noopener noreferrer"
            >
              <ExternalLink className="mr-2 h-4 w-4" />
              Documentation
            </a>
          </Button>
        )}
        <Button variant="outline" size="sm" asChild>
          <Link to="/studio/inspector" search={{ contributor: module.id }}>
            <Search className="mr-2 h-4 w-4" />
            View in Inspector
          </Link>
        </Button>
      </div>
    </div>
  );
}

// =============================================================================
// Health Tab
// =============================================================================

function HealthTab({
  module,
  onRefresh,
  isRefreshing,
}: {
  module: Module;
  onRefresh: () => void;
  isRefreshing: boolean;
}) {
  const health = module.health;

  if (!health) {
    return (
      <div className="flex flex-col items-center justify-center py-8 text-center">
        <Heart className="h-12 w-12 text-muted-foreground/30" />
        <p className="mt-4 text-sm text-muted-foreground">
          No health checks defined for this module
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Summary */}
      <div className="flex items-center justify-between rounded-lg border p-4">
        <div className="flex items-center gap-3">
          <HealthStatusIcon status={health.status} className="h-6 w-6" />
          <div>
            <p className="font-medium">{getHealthStatusLabel(health.status)}</p>
            <p className="text-sm text-muted-foreground">
              {health.healthyCount} of {health.totalCount} checks passing
            </p>
          </div>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={onRefresh}
          disabled={isRefreshing}
        >
          <RefreshCw
            className={cn("mr-2 h-4 w-4", isRefreshing && "animate-spin")}
          />
          Run Checks
        </Button>
      </div>

      {/* Last Updated */}
      {health.lastUpdated && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <Clock className="h-3 w-3" />
          Last updated: {new Date(health.lastUpdated).toLocaleString()}
        </div>
      )}

      {/* Individual Checks */}
      <div className="space-y-2">
        <h4 className="text-sm font-medium">Health Checks</h4>
        {health.checks.map((check) => (
          <HealthCheckItem key={check.checkId} check={check} />
        ))}
      </div>
    </div>
  );
}

function HealthCheckItem({ check }: { check: HealthcheckResult }) {
  return (
    <div
      className={cn(
        "rounded-md border p-3",
        check.status === "HEALTH_STATUS_UNHEALTHY" &&
          "border-red-500/30 bg-red-500/5",
        check.status === "HEALTH_STATUS_DEGRADED" &&
          "border-yellow-500/30 bg-yellow-500/5",
        check.status === "HEALTH_STATUS_HEALTHY" &&
          "border-green-500/30 bg-green-500/5",
      )}
    >
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-2">
          <HealthStatusIcon status={check.status} />
          <div>
            <p className="text-sm font-medium">
              {check.check?.name ?? check.checkId}
            </p>
            {check.check?.description && (
              <p className="text-xs text-muted-foreground">
                {check.check.description}
              </p>
            )}
          </div>
        </div>
        <span className="text-xs text-muted-foreground">
          {check.durationMs}ms
        </span>
      </div>

      {check.message && (
        <p className="mt-2 text-sm text-muted-foreground">{check.message}</p>
      )}

      {check.error && (
        <div className="mt-2 rounded bg-destructive/10 p-2 text-xs text-destructive">
          {check.error}
        </div>
      )}

      {check.output && (
        <pre className="mt-2 overflow-auto rounded bg-muted p-2 text-xs">
          {check.output}
        </pre>
      )}
    </div>
  );
}

// =============================================================================
// Main Component
// =============================================================================

export function ModuleDetailDrawer({
  moduleId,
  open,
  onOpenChange,
}: ModuleDetailDrawerProps) {
  const { data, isLoading, isError } = useModule(moduleId ?? "", {
    enabled: !!moduleId && open,
    includeHealth: true,
  });

  const enableMutation = useEnableModule(moduleId ?? "");
  const healthMutation = useRunModuleHealthchecks(moduleId ?? "");

  const module = data?.module;

  const handleToggleEnable = async (checked: boolean) => {
    if (moduleId) {
      await enableMutation.mutateAsync(checked);
    }
  };

  const handleRunHealthchecks = async () => {
    if (moduleId) {
      await healthMutation.mutateAsync();
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-lg px-4">
        {isLoading ? (
          <div className="flex h-full items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : isError || !module ? (
          <div className="flex h-full flex-col items-center justify-center gap-4">
            <AlertCircle className="h-12 w-12 text-destructive" />
            <p className="text-sm text-muted-foreground">
              Failed to load module details
            </p>
          </div>
        ) : (
          <>
            <SheetHeader>
              <div className="flex items-center justify-between pr-8">
                <div className="flex items-center gap-3">
                  <div>
                    <SheetTitle className="flex items-center gap-2">
                      {module.meta.name}
                      {module.source.type === "builtin" && (
                        <Badge variant="secondary" className="text-xs">
                          Builtin
                        </Badge>
                      )}
                    </SheetTitle>
                    <SheetDescription>{module.id}</SheetDescription>
                  </div>
                </div>
                <Switch
                  checked={module.enabled}
                  onCheckedChange={handleToggleEnable}
                  disabled={enableMutation.isPending}
                />
              </div>
            </SheetHeader>

            <Tabs defaultValue="overview" className="mt-6">
              <TabsList className="grid w-full grid-cols-3">
                <TabsTrigger value="overview" className="gap-1.5">
                  <Package className="h-3.5 w-3.5" />
                  Overview
                </TabsTrigger>
                <TabsTrigger value="config" className="gap-1.5">
                  <Settings className="h-3.5 w-3.5" />
                  Config
                </TabsTrigger>
                <TabsTrigger value="health" className="gap-1.5">
                  <Heart className="h-3.5 w-3.5" />
                  Health
                  {module.health && (
                    <HealthStatusIcon
                      status={module.health.status}
                      className="ml-1 h-3 w-3"
                    />
                  )}
                </TabsTrigger>
              </TabsList>

              <TabsContent value="overview" className="mt-4">
                <OverviewTab module={module} />
              </TabsContent>

              <TabsContent value="config" className="mt-4">
                <ModuleConfigForm
                  moduleId={moduleId!}
                  schema={module.configSchema}
                  initialConfig={data?.config}
                />
              </TabsContent>

              <TabsContent value="health" className="mt-4">
                <HealthTab
                  module={module}
                  onRefresh={handleRunHealthchecks}
                  isRefreshing={healthMutation.isPending}
                />
              </TabsContent>
            </Tabs>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
