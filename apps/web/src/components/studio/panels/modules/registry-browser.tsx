/**
 * Registry Browser
 *
 * Component for browsing and installing modules from the Stackpanel registry.
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import {
  Check,
  Cloud,
  Code,
  Database,
  Download,
  FileCode,
  Heart,
  Key,
  Loader2,
  Package,
  Puzzle,
  RefreshCw,
  Search,
  Sparkles,
  Star,
  Terminal,
} from "lucide-react";
import { useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import { useRegistryModules } from "./use-modules";
import { RegistryModuleDrawer } from "./registry-module-drawer";
import {
  type RegistryModule,
  MODULE_CATEGORIES,
  getCategoryLabel,
} from "./types";

// =============================================================================
// Feature Icons
// =============================================================================

function FeatureBadges({ features }: { features: RegistryModule["features"] }) {
  const featureList = [
    { key: "files", icon: FileCode, label: "Files" },
    { key: "scripts", icon: Terminal, label: "Scripts" },
    { key: "healthchecks", icon: Heart, label: "Health" },
    { key: "services", icon: Cloud, label: "Services" },
    { key: "secrets", icon: Key, label: "Secrets" },
    { key: "packages", icon: Package, label: "Packages" },
  ] as const;

  const activeFeatures = featureList.filter(
    (f) => features[f.key as keyof typeof features],
  );

  if (activeFeatures.length === 0) return null;

  return (
    <div className="flex flex-wrap gap-1">
      {activeFeatures.slice(0, 4).map(({ key, icon: Icon, label }) => (
        <Badge
          key={key}
          variant="outline"
          className="gap-1 px-1.5 py-0.5 text-xs"
        >
          <Icon className="h-3 w-3" />
          <span className="hidden sm:inline">{label}</span>
        </Badge>
      ))}
      {activeFeatures.length > 4 && (
        <Badge variant="outline" className="text-xs">
          +{activeFeatures.length - 4}
        </Badge>
      )}
    </div>
  );
}

// =============================================================================
// Registry Module Card
// =============================================================================

interface RegistryModuleCardProps {
  module: RegistryModule;
  onSelect: (module: RegistryModule) => void;
}

function RegistryModuleCard({ module, onSelect }: RegistryModuleCardProps) {
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
      case "monitoring":
        return Heart;
      default:
        return Puzzle;
    }
  }, [module.meta.category]);

  const CategoryIcon = categoryIcon;

  return (
    <Card className={cn(
      "transition-all",
      module.installed && "border-green-500/30 bg-green-500/5"
    )}>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-4">
          <div className="flex min-w-0 flex-1 items-start gap-3">
            <div className={cn(
              "flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg",
              module.builtin ? "bg-primary/10" : "bg-muted"
            )}>
              <CategoryIcon className={cn(
                "h-5 w-5",
                module.builtin ? "text-primary" : "text-muted-foreground"
              )} />
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <CardTitle className="truncate text-base">
                  {module.meta.name}
                </CardTitle>
                {module.installed && (
                  <Badge variant="outline" className="gap-1 text-xs text-green-600 border-green-600/30 bg-green-500/10">
                    <Check className="h-3 w-3" />
                    Installed
                  </Badge>
                )}
                {module.builtin && !module.installed && (
                  <Badge variant="default" className="gap-1 text-xs bg-primary/90">
                    <Sparkles className="h-3 w-3" />
                    Built-in
                  </Badge>
                )}
                {module.meta.version && (
                  <Badge variant="secondary" className="text-xs">
                    v{module.meta.version}
                  </Badge>
                )}
              </div>
              {module.meta.description && (
                <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                  {module.meta.description}
                </p>
              )}
            </div>
          </div>
        </div>
      </CardHeader>
      <CardContent className="pt-0">
        <div className="space-y-3">
          {/* Features */}
          <FeatureBadges features={module.features} />

          {/* Stats */}
          <div className="flex items-center gap-4 text-xs text-muted-foreground">
            {module.downloads !== undefined && (
              <div className="flex items-center gap-1">
                <Download className="h-3 w-3" />
                <span>{module.downloads.toLocaleString()}</span>
              </div>
            )}
            {module.rating !== undefined && (
              <div className="flex items-center gap-1">
                <Star className="h-3 w-3 fill-yellow-500 text-yellow-500" />
                <span>{module.rating.toFixed(1)}</span>
              </div>
            )}
            <span>{getCategoryLabel(module.meta.category)}</span>
          </div>

          {/* Tags */}
          {module.tags && module.tags.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {module.tags.slice(0, 4).map((tag) => (
                <Badge
                  key={tag}
                  variant="secondary"
                  className="text-[10px] px-1.5 py-0"
                >
                  {tag}
                </Badge>
              ))}
            </div>
          )}

          {/* View Details Button */}
          <div className="flex items-center justify-between pt-2">
            {module.meta.author && (
              <span className="text-xs text-muted-foreground">
                by {module.meta.author}
              </span>
            )}
            <Button
              size="sm"
              variant="outline"
              onClick={() => onSelect(module)}
            >
              View Details
            </Button>
          </div>
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
      <Package className="h-16 w-16 text-muted-foreground/50" />
      <div className="text-center">
        <h2 className="text-xl font-semibold">No Modules Available</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          The module registry is currently empty.
        </p>
      </div>
    </div>
  );
}

// =============================================================================
// Main Component
// =============================================================================

export function RegistryBrowser() {
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);
  const [selectedModule, setSelectedModule] = useState<RegistryModule | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [enableSuccess, setEnableSuccess] = useState<string | null>(null);

  const { data, isLoading, isError, error, refetch } = useRegistryModules({
    search: search || undefined,
    category: categoryFilter || undefined,
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

  const handleSelectModule = (module: RegistryModule) => {
    setSelectedModule(module);
    setDrawerOpen(true);
  };

  const handleEnableSuccess = (moduleName: string) => {
    setEnableSuccess(moduleName);
    // Clear success message after 5 seconds
    setTimeout(() => setEnableSuccess(null), 5000);
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
            Failed to load registry: {error?.message || "Unknown error"}
          </p>
        </div>
        <Button variant="outline" onClick={handleRefresh}>
          Try again
        </Button>
      </div>
    );
  }

  const modules = data?.modules ?? [];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold">Module Registry</h3>
          <p className="text-sm text-muted-foreground">
            Browse built-in modules and install community modules
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

      {/* Success Banner */}
      {enableSuccess && (
        <div className="flex items-center gap-3 rounded-lg border border-green-500/30 bg-green-500/10 p-4">
          <Check className="h-5 w-5 text-green-500" />
          <div>
            <p className="font-medium text-green-700 dark:text-green-400">
              {enableSuccess} enabled successfully!
            </p>
            <p className="text-sm text-muted-foreground">
              Re-enter your devshell to apply the changes.
            </p>
          </div>
        </div>
      )}

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
      </div>

      {/* Stats */}
      <div className="flex items-center gap-4 text-sm text-muted-foreground">
        <span>{data?.total ?? 0} modules available</span>
        {data?.sources && data.sources.length > 0 && (
          <>
            <span>•</span>
            <span>
              {data.sources.filter((s) => s.official).length} official source
              {data.sources.filter((s) => s.official).length !== 1 ? "s" : ""}
            </span>
          </>
        )}
      </div>

      {/* Module Grid */}
      {modules.length === 0 ? (
        <EmptyState hasFilter={!!search || !!categoryFilter} />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {modules.map((module) => (
            <RegistryModuleCard
              key={module.id}
              module={module}
              onSelect={handleSelectModule}
            />
          ))}
        </div>
      )}

      {/* Module Detail Drawer */}
      <RegistryModuleDrawer
        module={selectedModule}
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        onEnableSuccess={handleEnableSuccess}
      />
    </div>
  );
}
