/**
 * Extensions Page
 *
 * Displays true extensions (optional add-ons like SST) - NOT core modules.
 * Core modules (Go, Caddy, Healthchecks) have their panels shown on the Dashboard.
 *
 * Extensions are optional features that can be enabled/disabled and may provide:
 * - File generation
 * - Scripts/commands
 * - Secrets management
 * - UI panels
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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { createFileRoute } from "@tanstack/react-router";
import {
  Check,
  ChevronDown,
  ChevronRight,
  Cloud,
  Code,
  ExternalLink,
  FileCode,
  Key,
  Loader2,
  Package,
  Puzzle,
  RefreshCw,
  Search,
  Terminal,
  X,
} from "lucide-react";
import { useState } from "react";
import { useNixConfig } from "@/lib/use-nix-config";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/studio/extensions")({
  component: ExtensionsPage,
});

// =============================================================================
// Types
// =============================================================================

interface ExtensionFeatures {
  files?: boolean;
  scripts?: boolean;
  tasks?: boolean;
  secrets?: boolean;
  "shell-hooks"?: boolean;
  packages?: boolean;
  services?: boolean;
  checks?: boolean;
}

interface ExtensionPanel {
  id: string;
  title: string;
  description?: string | null;
  type: string;
  order: number;
  fields: Array<{
    name: string;
    type: string;
    value: string;
  }>;
}

interface Extension {
  name: string;
  description?: string | null;
  enabled: boolean;
  builtin?: boolean;
  priority?: number;
  tags?: string[];
  features?: ExtensionFeatures;
  panels?: ExtensionPanel[];
  source?: {
    type: string;
    repo?: string | null;
    path?: string | null;
  };
}

// =============================================================================
// Main Component
// =============================================================================

function ExtensionsPage() {
  const { data: config, isLoading, isError, error, refetch } = useNixConfig();
  const [filter, setFilter] = useState("");
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await refetch();
    } finally {
      setIsRefreshing(false);
    }
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
            Failed to load extensions: {error?.message || "Unknown error"}
          </p>
        </div>
        <Button variant="outline" onClick={handleRefresh}>
          Try again
        </Button>
      </div>
    );
  }

  // Extract extensions from config
  const configRecord = config as Record<string, unknown> | undefined;
  const extensions = configRecord?.extensions as
    | Record<string, Extension>
    | undefined;

  // Filter to only show true extensions (not core modules pretending to be extensions)
  // Core modules will be shown via the panels system on the Dashboard
  const trueExtensions = extensions
    ? Object.entries(extensions).filter(([_, ext]) => {
        // SST and similar are true extensions
        // They typically have builtin=true or have features defined
        return ext.enabled;
      })
    : [];

  // Apply text filter
  const filteredExtensions = trueExtensions.filter(([key, ext]) => {
    if (!filter) return true;
    const searchLower = filter.toLowerCase();
    return (
      key.toLowerCase().includes(searchLower) ||
      ext.name.toLowerCase().includes(searchLower) ||
      ext.description?.toLowerCase().includes(searchLower) ||
      ext.tags?.some((tag) => tag.toLowerCase().includes(searchLower))
    );
  });

  // Sort by priority
  const sortedExtensions = filteredExtensions.sort(
    ([, a], [, b]) => (a.priority ?? 100) - (b.priority ?? 100),
  );

  // Count stats
  const enabledCount = trueExtensions.filter(([, e]) => e.enabled).length;
  const builtinCount = trueExtensions.filter(([, e]) => e.builtin).length;

  return (
    <div className="container mx-auto space-y-6 py-8">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <h1 className="flex items-center gap-2 text-3xl font-bold">
            <Puzzle className="h-8 w-8" />
            Extensions
          </h1>
          <p className="text-muted-foreground">
            Optional add-ons that extend Stackpanel functionality
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

      {/* Stats Card */}
      <Card>
        <CardContent className="py-4">
          <div className="flex items-center gap-6 text-sm">
            <div className="flex items-center gap-2">
              <Package className="h-4 w-4 text-muted-foreground" />
              <span className="font-medium">{enabledCount}</span>
              <span className="text-muted-foreground">extensions enabled</span>
            </div>
            <div className="h-4 w-px bg-border" />
            <div className="flex items-center gap-2">
              <Cloud className="h-4 w-4 text-blue-500" />
              <span className="font-medium">{builtinCount}</span>
              <span className="text-muted-foreground">builtin</span>
            </div>
            <div className="h-4 w-px bg-border" />
            <div className="flex items-center gap-2">
              <ExternalLink className="h-4 w-4 text-green-500" />
              <span className="font-medium">{enabledCount - builtinCount}</span>
              <span className="text-muted-foreground">external</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Filter */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Filter extensions..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="pl-10"
        />
      </div>

      {/* Extensions List */}
      {sortedExtensions.length === 0 ? (
        <EmptyState hasFilter={!!filter} />
      ) : (
        <div className="space-y-3">
          {sortedExtensions.map(([key, extension]) => (
            <ExtensionItem key={key} extension={extension} />
          ))}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Extension Item Component
// =============================================================================

function ExtensionItem({ extension }: { extension: Extension }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <Collapsible open={expanded} onOpenChange={setExpanded}>
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
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <CardTitle className="text-base">
                      {extension.name}
                    </CardTitle>
                    {extension.builtin && (
                      <Badge variant="secondary" className="text-xs">
                        Builtin
                      </Badge>
                    )}
                  </div>
                  {extension.description && (
                    <p className="text-sm text-muted-foreground">
                      {extension.description}
                    </p>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-3">
                {extension.tags && extension.tags.length > 0 && (
                  <div className="hidden sm:flex gap-1">
                    {extension.tags.slice(0, 3).map((tag) => (
                      <Badge key={tag} variant="outline" className="text-xs">
                        {tag}
                      </Badge>
                    ))}
                    {extension.tags.length > 3 && (
                      <Badge variant="outline" className="text-xs">
                        +{extension.tags.length - 3}
                      </Badge>
                    )}
                  </div>
                )}
                <Badge
                  variant={extension.enabled ? "default" : "secondary"}
                  className={cn(
                    "text-xs",
                    extension.enabled &&
                      "bg-green-500/10 text-green-600 border-green-500/30 hover:bg-green-500/20",
                  )}
                >
                  {extension.enabled ? "Enabled" : "Disabled"}
                </Badge>
              </div>
            </div>
          </CardHeader>
        </CollapsibleTrigger>

        <CollapsibleContent>
          <CardContent className="border-t pt-4">
            <ExtensionDetails extension={extension} />
          </CardContent>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}

// =============================================================================
// Extension Details Component
// =============================================================================

function ExtensionDetails({ extension }: { extension: Extension }) {
  return (
    <Tabs defaultValue="features" className="w-full">
      <TabsList className="grid w-full grid-cols-3">
        <TabsTrigger value="features" className="gap-1.5">
          <Package className="h-3.5 w-3.5" />
          Features
        </TabsTrigger>
        <TabsTrigger value="panels" className="gap-1.5">
          <Code className="h-3.5 w-3.5" />
          Panels
          {extension.panels && extension.panels.length > 0 && (
            <Badge variant="secondary" className="ml-1 text-xs">
              {extension.panels.length}
            </Badge>
          )}
        </TabsTrigger>
        <TabsTrigger value="source" className="gap-1.5">
          <FileCode className="h-3.5 w-3.5" />
          Source
        </TabsTrigger>
      </TabsList>

      <TabsContent value="features" className="mt-4">
        <FeaturesTab features={extension.features} />
      </TabsContent>

      <TabsContent value="panels" className="mt-4">
        <PanelsTab panels={extension.panels} />
      </TabsContent>

      <TabsContent value="source" className="mt-4">
        <SourceTab extension={extension} />
      </TabsContent>
    </Tabs>
  );
}

// =============================================================================
// Tab Components
// =============================================================================

function FeaturesTab({ features }: { features?: ExtensionFeatures }) {
  if (!features) {
    return (
      <p className="text-sm text-muted-foreground">
        No features declared for this extension.
      </p>
    );
  }

  const featureList = [
    { key: "files", label: "File Generation", icon: FileCode },
    { key: "scripts", label: "Shell Scripts", icon: Terminal },
    { key: "secrets", label: "Secrets Management", icon: Key },
    { key: "packages", label: "Devshell Packages", icon: Package },
    { key: "tasks", label: "Tasks", icon: Code },
    { key: "services", label: "Services", icon: Cloud },
  ];

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
      {featureList.map(({ key, label, icon: Icon }) => {
        const enabled = features[key as keyof ExtensionFeatures];
        return (
          <div
            key={key}
            className={cn(
              "flex items-center gap-2 rounded-lg border p-3 transition-colors",
              enabled
                ? "border-green-500/30 bg-green-500/5"
                : "border-muted bg-muted/30 opacity-50",
            )}
          >
            {enabled ? (
              <Check className="h-4 w-4 text-green-500" />
            ) : (
              <X className="h-4 w-4 text-muted-foreground" />
            )}
            <Icon className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm">{label}</span>
          </div>
        );
      })}
    </div>
  );
}

function PanelsTab({ panels }: { panels?: ExtensionPanel[] }) {
  if (!panels || panels.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        This extension does not provide any UI panels.
      </p>
    );
  }

  return (
    <div className="space-y-3">
      {panels.map((panel) => (
        <div key={panel.id} className="rounded-lg border p-3">
          <div className="flex items-center justify-between">
            <div>
              <h4 className="font-medium">{panel.title}</h4>
              {panel.description && (
                <p className="text-sm text-muted-foreground">
                  {panel.description}
                </p>
              )}
            </div>
            <Badge variant="outline" className="text-xs">
              {panel.type.replace("PANEL_TYPE_", "")}
            </Badge>
          </div>
        </div>
      ))}
    </div>
  );
}

function SourceTab({ extension }: { extension: Extension }) {
  const source = extension.source;

  return (
    <div className="space-y-3">
      <div className="grid gap-2 text-sm">
        <div className="flex items-center gap-2">
          <span className="text-muted-foreground w-20">Type:</span>
          <Badge variant="outline">
            {source?.type?.replace("EXTENSION_SOURCE_TYPE_", "") || "Builtin"}
          </Badge>
        </div>
        {source?.repo && (
          <div className="flex items-center gap-2">
            <span className="text-muted-foreground w-20">Repository:</span>
            <code className="rounded bg-muted px-2 py-0.5 text-xs">
              {source.repo}
            </code>
          </div>
        )}
        {source?.path && (
          <div className="flex items-center gap-2">
            <span className="text-muted-foreground w-20">Path:</span>
            <code className="rounded bg-muted px-2 py-0.5 text-xs">
              {source.path}
            </code>
          </div>
        )}
        {extension.priority !== undefined && (
          <div className="flex items-center gap-2">
            <span className="text-muted-foreground w-20">Priority:</span>
            <span>{extension.priority}</span>
          </div>
        )}
      </div>
    </div>
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
          <h2 className="text-lg font-semibold">No matching extensions</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Try adjusting your search filter
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-[300px] flex-col items-center justify-center gap-4">
      <Puzzle className="h-16 w-16 text-muted-foreground/50" />
      <div className="text-center">
        <h2 className="text-xl font-semibold">No Extensions Installed</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Extensions are optional add-ons that provide additional functionality.
        </p>
        <p className="mt-4 text-xs text-muted-foreground">
          Enable extensions in your Nix config with{" "}
          <code className="rounded bg-muted px-1.5 py-0.5">
            stackpanel.&lt;extension&gt;.enable = true
          </code>
        </p>
      </div>
    </div>
  );
}
