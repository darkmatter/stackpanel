"use client";

import {
  AlertTriangle,
  Check,
  Database,
  ExternalLink,
  Loader2,
  Package,
  Plus,
  RefreshCw,
  Search,
  Trash2,
  X,
  Zap,
} from "lucide-react";
import { useCallback, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { useNixpkgsSearch, type DataSource } from "@/lib/use-nixpkgs-search";
import { useInstalledPackages } from "@/lib/use-installed-packages";
import { useNixData } from "@/lib/use-nix-config";
import type { NixpkgsPackage } from "@/lib/types";

interface SearchErrorMessageProps {
  error: Error;
}

function SearchErrorMessage({ error }: SearchErrorMessageProps) {
  const isNoProject = error.message.includes("no project");

  if (isNoProject) {
    return (
      <div className="rounded-lg border border-amber-500/50 bg-amber-500/10 p-4">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-amber-500 shrink-0 mt-0.5" />
          <div>
            <p className="font-medium text-amber-600 dark:text-amber-400">
              No project connected
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              Package search requires a connected project with a devshell
              environment. Make sure you have a project open and the agent is
              running.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4 text-destructive text-sm">
      <p className="font-medium">Failed to search packages</p>
      <p className="mt-1 text-destructive/80">{error.message}</p>
    </div>
  );
}

interface DataSourceIndicatorProps {
  source: DataSource;
  isRefreshing: boolean;
  cacheStats: { packageCount: number; searchCount: number } | null;
}

function DataSourceIndicator({
  source,
  isRefreshing,
  cacheStats,
}: DataSourceIndicatorProps) {
  if (isRefreshing) {
    return (
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="inline-flex items-center gap-1.5 text-xs text-muted-foreground">
              <RefreshCw className="h-3 w-3 animate-spin" />
              <span>Fetching latest...</span>
            </div>
          </TooltipTrigger>
          <TooltipContent>
            Showing cached results while fetching fresh data
          </TooltipContent>
        </Tooltip>
      </TooltipProvider>
    );
  }

  if (source === "fresh") {
    return (
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="inline-flex items-center gap-1.5 text-xs text-green-600 dark:text-green-400">
              <Zap className="h-3 w-3" />
              <span>Fresh</span>
            </div>
          </TooltipTrigger>
          <TooltipContent>
            Results fetched from nixpkgs
            {cacheStats && cacheStats.packageCount > 0 && (
              <div className="text-muted-foreground mt-1">
                {cacheStats.packageCount.toLocaleString()} packages cached
              </div>
            )}
          </TooltipContent>
        </Tooltip>
      </TooltipProvider>
    );
  }

  if (source === "cache") {
    return (
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="inline-flex items-center gap-1.5 text-xs text-blue-600 dark:text-blue-400">
              <Database className="h-3 w-3" />
              <span>Cached</span>
            </div>
          </TooltipTrigger>
          <TooltipContent>Showing cached results (still fresh)</TooltipContent>
        </Tooltip>
      </TooltipProvider>
    );
  }

  if (source === "local") {
    return (
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="inline-flex items-center gap-1.5 text-xs text-amber-600 dark:text-amber-400">
              <Database className="h-3 w-3" />
              <span>Local</span>
            </div>
          </TooltipTrigger>
          <TooltipContent>Searching locally cached packages</TooltipContent>
        </Tooltip>
      </TooltipProvider>
    );
  }

  return null;
}

interface PackageCardProps {
  pkg: NixpkgsPackage;
  isInstalled?: boolean;
  isUserInstalled?: boolean;
  isAdding?: boolean;
  isRemoving?: boolean;
  isCompact?: boolean;
  onAdd?: (pkg: NixpkgsPackage) => void;
  onRemove?: (pkg: NixpkgsPackage) => void;
}

function PackageCard({
  pkg,
  isInstalled = false,
  isUserInstalled = false,
  isAdding = false,
  isRemoving = false,
  isCompact = false,
  onAdd,
  onRemove,
}: PackageCardProps) {
  const isProcessing = isAdding || isRemoving;

  return (
    <Card
      className={`transition-colors ${isInstalled ? "border-green-500/30 bg-green-600/2" : "hover:border-accent/50"}`}
    >
      <CardContent className={isCompact ? "p-2.5" : "p-4"}>
        <div
          className={`flex items-start justify-between ${isCompact ? "gap-3" : "gap-4"}`}
        >
          <div
            className={`flex items-start min-w-0 flex-1 ${isCompact ? "gap-2.5" : "gap-3"}`}
          >
            <div
              className={`flex shrink-0 items-center justify-center rounded-lg ${isCompact ? "h-8 w-8" : "h-10 w-10"} ${isInstalled ? "bg-green-500/10" : "bg-accent/10"}`}
            >
              {isInstalled ? (
                <Check
                  className={
                    isCompact
                      ? "h-4 w-4 text-green-500"
                      : "h-5 w-5 text-green-500"
                  }
                />
              ) : (
                <Package
                  className={
                    isCompact ? "h-4 w-4 text-accent" : "h-5 w-5 text-accent"
                  }
                />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 flex-wrap">
                <h3
                  className={`font-medium text-foreground truncate ${isCompact ? "text-sm" : ""}`}
                >
                  {pkg.name}
                </h3>
                <Badge variant="secondary" className="text-xs shrink-0">
                  {pkg.version}
                </Badge>
                {isInstalled && (
                  <Badge
                    variant="outline"
                    className="text-xs shrink-0 border-green-500/50 text-green-600 dark:text-green-600"
                  >
                    {isUserInstalled ? "User Installed" : "From Config"}
                  </Badge>
                )}
              </div>
              <p className="mt-0.5 text-muted-foreground text-xs font-mono truncate">
                {pkg.attr_path}
              </p>
              {pkg.description && (
                <p
                  className={`text-muted-foreground line-clamp-2 ${isCompact ? "mt-1 text-xs" : "mt-2 text-sm"}`}
                >
                  {pkg.description}
                </p>
              )}
              <div
                className={`flex items-center gap-2 flex-wrap ${isCompact ? "mt-1" : "mt-2"}`}
              >
                {pkg.license && (
                  <Badge variant="outline" className="text-xs">
                    {pkg.license}
                  </Badge>
                )}
                {pkg.nixpkgs_url && (
                  <a
                    href={pkg.nixpkgs_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-accent transition-colors"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <ExternalLink className="h-3 w-3" />
                    Nixpkgs
                  </a>
                )}
                {pkg.homepage && (
                  <a
                    href={pkg.homepage}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-accent transition-colors"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <ExternalLink className="h-3 w-3" />
                    Homepage
                  </a>
                )}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {/* Remove button for user-installed packages */}
            {isUserInstalled && onRemove && (
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      size="sm"
                      variant="outline"
                      className="shrink-0 cursor-pointer hover:text-destructive hover:border-destructive"
                      onClick={() => onRemove(pkg)}
                      disabled={isProcessing}
                    >
                      {isRemoving ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        <Trash2 className="h-4 w-4" />
                      )}
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>Remove from devshell</TooltipContent>
                </Tooltip>
              </TooltipProvider>
            )}
            {/* Add button for non-installed packages */}
            {onAdd && !isInstalled && (
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      size="sm"
                      variant="outline"
                      className="shrink-0 cursor-pointer hover:text-accent-foreground"
                      onClick={() => onAdd(pkg)}
                      disabled={isProcessing}
                    >
                      {isAdding ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        <Plus className="h-4 w-4" />
                      )}
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>Add to devshell</TooltipContent>
                </Tooltip>
              </TooltipProvider>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

export function PackagesPanel() {
  const {
    query,
    setQuery,
    packages,
    total,
    isLoading,
    isRefreshing,
    error,
    hasMore,
    loadMore,
    clear,
    dataSource,
    cacheStats,
  } = useNixpkgsSearch();

  // Fetch installed packages separately for accurate status across the UI
  const {
    packages: installedPackages,
    isInstalled: checkInstalled,
    count: installedCount,
    refresh: refreshInstalled,
  } = useInstalledPackages();

  // User packages from .stackpanel/data/packages.nix
  const { data: userPackages, mutate: setUserPackages } = useNixData<string[]>(
    "packages",
    { initialData: [] },
  );

  // Track packages currently being added/removed
  const [processingPackages, setProcessingPackages] = useState<
    Map<string, "adding" | "removing">
  >(new Map());
  const [showInstalled, setShowInstalled] = useState(true);

  // Add a package to user packages
  const handleAddPackage = useCallback(
    async (pkg: NixpkgsPackage) => {
      const attrPath = pkg.attr_path;
      const currentPackages = userPackages ?? [];

      // Don't add if already in list
      if (currentPackages.includes(attrPath)) {
        return;
      }

      setProcessingPackages((prev) => new Map(prev).set(attrPath, "adding"));

      try {
        const newPackages = [...currentPackages, attrPath];
        await setUserPackages(newPackages);
        // Refresh installed packages to reflect the change
        await refreshInstalled();
      } catch (err) {
        console.error("Failed to add package:", err);
      } finally {
        setProcessingPackages((prev) => {
          const next = new Map(prev);
          next.delete(attrPath);
          return next;
        });
      }
    },
    [userPackages, setUserPackages, refreshInstalled],
  );

  // Remove a package from user packages
  const handleRemovePackage = useCallback(
    async (pkg: NixpkgsPackage) => {
      const attrPath = pkg.attr_path;
      const currentPackages = userPackages ?? [];

      setProcessingPackages((prev) => new Map(prev).set(attrPath, "removing"));

      try {
        const newPackages = currentPackages.filter((p) => p !== attrPath);
        await setUserPackages(newPackages);
        // Refresh installed packages to reflect the change
        await refreshInstalled();
      } catch (err) {
        console.error("Failed to remove package:", err);
      } finally {
        setProcessingPackages((prev) => {
          const next = new Map(prev);
          next.delete(attrPath);
          return next;
        });
      }
    },
    [userPackages, setUserPackages, refreshInstalled],
  );

  // Check if a package is installed (from any source)
  const isPackageInstalled = (pkg: NixpkgsPackage): boolean => {
    return checkInstalled(pkg.name) || checkInstalled(pkg.attr_path);
  };

  // Check if a package is user-installed (from .stackpanel/data/packages.nix)
  const isUserInstalledPackage = (pkg: NixpkgsPackage): boolean => {
    const currentPackages = userPackages ?? [];
    return currentPackages.includes(pkg.attr_path);
  };

  // Get user-installed packages for display
  const userInstalledPackages = installedPackages.filter(
    (pkg) => pkg.source === "user",
  );

  // Get devshell packages (from Nix config)
  const devshellPackages = installedPackages.filter(
    (pkg) => pkg.source !== "user",
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="font-semibold text-foreground text-xl">Packages</h2>
          <p className="text-muted-foreground text-sm">
            Search and add packages from nixpkgs to your development environment
          </p>
        </div>
        <div className="flex items-center gap-4 text-xs text-muted-foreground">
          {!query && installedCount > 0 && (
            <span className="text-green-600 dark:text-green-400">
              {installedCount} installed
            </span>
          )}
          {cacheStats && cacheStats.packageCount > 0 && (
            <span>{cacheStats.packageCount.toLocaleString()} cached</span>
          )}
          {!query && (
            <div className="flex items-center gap-2">
              <Label
                htmlFor="show-installed-packages"
                className="text-xs text-muted-foreground"
              >
                Show installed
              </Label>
              <Switch
                id="show-installed-packages"
                checked={showInstalled}
                onCheckedChange={setShowInstalled}
              />
            </div>
          )}
        </div>
      </div>

      {/* Search Controls */}
      <div className="relative">
        {isLoading || isRefreshing ? (
          <Loader2 className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-accent animate-spin" />
        ) : (
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        )}
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search nixpkgs packages..."
          className="pl-9 pr-9"
        />
        {query && (
          <button
            onClick={clear}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>

      {/* Results Info with Data Source */}
      {query && !isLoading && !error && (
        <div className="flex items-center justify-between">
          <div className="text-sm text-muted-foreground">
            {total > 0 ? (
              <>
                Found <strong>{total.toLocaleString()}</strong> packages
                matching "{query}"
              </>
            ) : (
              <>No packages found matching "{query}"</>
            )}
          </div>
          {dataSource && (
            <DataSourceIndicator
              source={dataSource}
              isRefreshing={isRefreshing}
              cacheStats={cacheStats}
            />
          )}
        </div>
      )}

      {/* Error State */}
      {error && <SearchErrorMessage error={error} />}

      {/* Loading State (initial, no cached results) */}
      {isLoading && packages.length === 0 && (
        <div className="flex flex-col items-center justify-center py-12 gap-3">
          <Loader2 className="h-8 w-8 animate-spin text-accent" />
          <p className="text-sm text-muted-foreground">Searching nixpkgs...</p>
        </div>
      )}

      {/* Empty State */}
      {!query &&
        !isLoading &&
        !error &&
        (!showInstalled || installedCount === 0) && (
          <div className="flex flex-col items-center justify-center py-12 text-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-accent/10">
              <Package className="h-8 w-8 text-accent" />
            </div>
            <h3 className="mt-4 font-medium text-foreground">Search Nixpkgs</h3>
            <p className="mt-2 max-w-sm text-muted-foreground text-sm">
              Search over 100,000 packages in the Nix package collection. Find
              tools, libraries, and applications for your development
              environment.
            </p>
            {installedCount > 0 && !showInstalled && (
              <p className="mt-3 text-xs text-muted-foreground">
                Toggle “Show installed” to view your current packages.
              </p>
            )}
            {cacheStats && cacheStats.packageCount > 0 && (
              <p className="mt-3 text-xs text-muted-foreground">
                <Database className="inline h-3 w-3 mr-1" />
                {cacheStats.packageCount.toLocaleString()} packages cached for
                instant results
              </p>
            )}
          </div>
        )}

      {/* User-installed packages section */}
      {showInstalled && userInstalledPackages.length > 0 && !query && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-medium text-muted-foreground">
              User-installed packages
            </h3>
            <Badge variant="secondary" className="text-xs">
              {userInstalledPackages.length}
            </Badge>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            {userInstalledPackages.map((pkg) => {
              const attrPath = pkg.attrPath || pkg.name;
              const processing = processingPackages.get(attrPath);
              return (
                <PackageCard
                  key={attrPath}
                  pkg={{
                    name: pkg.name,
                    attr_path: attrPath,
                    version: pkg.version || "",
                    description: "",
                  }}
                  isInstalled={true}
                  isUserInstalled={true}
                  isCompact={true}
                  isRemoving={processing === "removing"}
                  onRemove={(p) => handleRemovePackage(p)}
                />
              );
            })}
          </div>
        </div>
      )}

      {/* Devshell packages section */}
      {showInstalled && devshellPackages.length > 0 && !query && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-medium text-muted-foreground">
              From devshell config
            </h3>
            <Badge variant="secondary" className="text-xs">
              {devshellPackages.length}
            </Badge>
          </div>
          <div className="text-xs text-muted-foreground">
            These packages are defined in your Nix configuration and cannot be
            removed from the UI.
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            {devshellPackages.map((pkg) => {
              const attrPath = pkg.attrPath || pkg.name;
              return (
                <PackageCard
                  key={attrPath}
                  pkg={{
                    name: pkg.name,
                    attr_path: attrPath,
                    version: pkg.version || "",
                    description: "",
                  }}
                  isInstalled={true}
                  isUserInstalled={false}
                  isCompact={true}
                />
              );
            })}
          </div>
        </div>
      )}

      {/* Search Results */}
      {packages.length > 0 && query && (
        <div className="space-y-3">
          {packages.map((pkg) => {
            const installed = isPackageInstalled(pkg);
            const userInstalled = isUserInstalledPackage(pkg);
            const processing = processingPackages.get(pkg.attr_path);
            return (
              <PackageCard
                key={pkg.attr_path}
                pkg={pkg}
                isInstalled={installed}
                isUserInstalled={userInstalled}
                isAdding={processing === "adding"}
                isRemoving={processing === "removing"}
                onAdd={installed ? undefined : handleAddPackage}
                onRemove={userInstalled ? handleRemovePackage : undefined}
              />
            );
          })}
        </div>
      )}

      {/* Load More */}
      {hasMore && (
        <div className="flex justify-center pt-4">
          <Button
            variant="outline"
            onClick={loadMore}
            disabled={isLoading || isRefreshing}
            className="gap-2"
          >
            {isLoading || isRefreshing ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Loading...
              </>
            ) : (
              <>
                Load More
                <Badge variant="secondary" className="ml-1">
                  {packages.length} / {total}
                </Badge>
              </>
            )}
          </Button>
        </div>
      )}
    </div>
  );
}
