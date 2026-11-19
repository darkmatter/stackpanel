import type { Module } from "@stackpanel/proto/agent/v1/module";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader } from "@ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@ui/collapsible";
import { Input } from "@ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@ui/select";
import { Switch } from "@ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import {
  Check,
  ChevronDown,
  ChevronRight,
  FolderGit,
  Loader2,
  Package,
  Puzzle,
  RefreshCw,
  Search,
  Settings,
} from "lucide-react";
import { useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import { getModuleIconByName } from "../shared/module-icons";
import { PanelHeader } from "../shared/panel-header";
import { ModuleDetailDrawer } from "./module-detail-drawer";
import { ModuleFeatures } from "./module-features";
import { ModuleEnableControl, ShellRebuildPrompt } from "./module-lifecycle-controls";
import { RegistryBrowser } from "./registry-browser";
import { RegistryModuleDrawer } from "./registry-module-drawer";
import { getCategoryLabel, getSourceLabel } from "./module-labels";
import { useModuleCatalog, useModuleQueryScope } from "./use-modules";

function ModuleCard({
  module,
  onSelect,
  onChanged,
}: {
  module: Module;
  onSelect: () => void;
  onChanged?: (message: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const Icon = getModuleIconByName(module.meta?.icon);
  const Chevron = expanded ? ChevronDown : ChevronRight;

  return (
    <Collapsible open={expanded} onOpenChange={setExpanded}>
      <Card className={cn("transition-all", !module.enabled && "opacity-75")}>
        <CardHeader className="flex flex-row items-center justify-between gap-4 py-4">
          <CollapsibleTrigger asChild>
            <button
              type="button"
              className="flex min-w-0 flex-1 items-center gap-3 text-left hover:text-primary"
            >
              <Chevron className="h-4 w-4 shrink-0 text-muted-foreground" />
              <Icon className="h-5 w-5 shrink-0 text-muted-foreground" />
              <span className="min-w-0 flex-1">
                <span className="flex items-center gap-2">
                  <span className="truncate text-base font-semibold">
                    {module.meta?.name || module.id}
                  </span>
                  {module.source?.type === "builtin" && <Badge variant="secondary">Builtin</Badge>}
                  {module.source?.type === "flake-input" && (
                    <Badge variant="outline" className="gap-1 text-blue-500">
                      <FolderGit className="h-3 w-3" />
                      Flake
                    </Badge>
                  )}
                </span>
                {module.meta?.description && (
                  <span className="block truncate text-sm text-muted-foreground">
                    {module.meta.description}
                  </span>
                )}
              </span>
            </button>
          </CollapsibleTrigger>
          {onChanged ? (
            <ModuleEnableControl
              moduleId={module.id}
              enabled={module.enabled}
              onChanged={onChanged}
            />
          ) : (
            <Button variant="outline" onClick={onSelect}>
              Manage
            </Button>
          )}
        </CardHeader>
        <CollapsibleContent>
          <CardContent className="space-y-4 border-t pt-4">
            <ModuleFeatures values={module.features} compact />
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <Badge variant="outline">{getSourceLabel(module.source?.type)}</Badge>
              <span>{getCategoryLabel(module.meta?.category)}</span>
              {module.meta?.version && (
                <span className="text-muted-foreground">v{module.meta.version}</span>
              )}
              {module.tags.map((tag) => (
                <Badge key={tag} variant="secondary">
                  {tag}
                </Badge>
              ))}
            </div>
            <Button variant="outline" size="sm" onClick={onSelect}>
              <Settings className="mr-2 h-4 w-4" />
              Configure
            </Button>
          </CardContent>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}

function InstalledModules({ onSelect }: { onSelect: (id: string) => void }) {
  const { data, error, isFetching, refetch } = useModuleCatalog();
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("");
  const [showDisabled, setShowDisabled] = useState(true);
  const [change, setChange] = useState({ count: 0, message: "" });
  const categories = useMemo(
    () =>
      [
        ...new Set(data?.modules.flatMap(({ meta }) => (meta?.category ? [meta.category] : []))),
      ].sort(),
    [data],
  );
  const modules = useMemo(() => {
    const term = search.trim().toLowerCase();
    return (data?.modules ?? [])
      .filter(
        (module) =>
          (showDisabled || module.enabled) &&
          (!category || module.meta?.category === category) &&
          (!term ||
            [module.id, module.meta?.name, module.meta?.description, ...module.tags].some((value) =>
              value?.toLowerCase().includes(term),
            )),
      )
      .sort(
        (a, b) =>
          a.priority - b.priority || (a.meta?.name || a.id).localeCompare(b.meta?.name || b.id),
      );
  }, [data, search, category, showDisabled]);

  if (error) {
    return (
      <div className="flex min-h-[300px] flex-col items-center justify-center gap-4">
        <p role="alert" className="text-sm text-destructive">
          Failed to load project modules: {error.message}
        </p>
        <Button variant="outline" onClick={() => void refetch()} disabled={isFetching}>
          Try again
        </Button>
      </div>
    );
  }
  if (!data)
    return (
      <div role="status" className="flex justify-center gap-2 py-12 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" />
        Loading project modules…
      </div>
    );
  const filtered = search.trim() !== "" || category !== "" || !showDisabled;
  return (
    <>
      {change.count > 0 && <ShellRebuildPrompt key={change.count} message={change.message} />}
      <div className="flex items-center justify-between gap-2">
        <Card className="py-4">
          <CardContent className="flex flex-wrap items-center gap-2 text-sm sm:gap-4">
            <Package className="h-4 w-4 text-muted-foreground" />
            <span>{data.modules.length} total</span>
            <span className="h-4 w-px bg-border" />
            <Check className="h-4 w-4 text-green-500" />
            <span>{data.modules.filter((module) => module.enabled).length} enabled</span>
          </CardContent>
        </Card>
        <Button variant="outline" size="sm" onClick={() => void refetch()} disabled={isFetching}>
          <RefreshCw className={cn("mr-2 h-4 w-4", isFetching && "animate-spin")} />
          Refresh
        </Button>
      </div>
      <div className="flex flex-col gap-3 sm:flex-row">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            aria-label="Search project modules"
            placeholder="Search modules..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select
          value={category ? `category:${category}` : "all"}
          onValueChange={(v) => setCategory(v === "all" ? "" : v.slice("category:".length))}
        >
          <SelectTrigger aria-label="Filter by category" className="w-full sm:w-[180px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All categories</SelectItem>
            {categories.map((cat) => (
              <SelectItem key={cat} value={`category:${cat}`}>
                {getCategoryLabel(cat)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <div className="flex items-center gap-2">
          <Switch id="show-disabled" checked={showDisabled} onCheckedChange={setShowDisabled} />
          <label htmlFor="show-disabled" className="text-sm">
            Show disabled
          </label>
        </div>
      </div>
      {modules.length === 0 ? (
        <div className="flex min-h-[200px] flex-col items-center justify-center gap-2 text-center">
          <Puzzle className="mb-2 h-12 w-12 text-muted-foreground/50" />
          <h3 className="text-lg font-semibold">
            {filtered ? "No matching modules" : "No modules found"}
          </h3>
          <p className="text-sm text-muted-foreground">
            {filtered
              ? "Try adjusting your search or filters."
              : "Add modules in your Nix config or install one from the registry."}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {modules.map((module) => (
            <ModuleCard
              key={module.id}
              module={module}
              onSelect={() => onSelect(module.id)}
              // Disable from the drawer when the row will disappear on refetch.
              onChanged={
                showDisabled
                  ? (message) => setChange((prev) => ({ count: prev.count + 1, message }))
                  : undefined
              }
            />
          ))}
        </div>
      )}
    </>
  );
}

type Selection = { drawer: "module" | "registry"; id: string };

function ProjectModulesPanel() {
  const [selection, setSelection] = useState<Selection | null>(null);
  const close = (open: boolean) => {
    if (!open) setSelection(null);
  };
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
          </TabsTrigger>
        </TabsList>
        <TabsContent value="registry" className="mt-6">
          <RegistryBrowser />
        </TabsContent>
        <TabsContent value="installed" className="mt-6 space-y-6">
          <InstalledModules onSelect={(id) => setSelection({ drawer: "module", id })} />
        </TabsContent>
      </Tabs>
      {selection?.drawer === "module" && (
        <ModuleDetailDrawer
          key={selection.id}
          moduleId={selection.id}
          open
          onOpenChange={close}
          onManageRegistry={(id) => setSelection({ drawer: "registry", id })}
        />
      )}
      {selection?.drawer === "registry" && (
        <RegistryModuleDrawer
          key={selection.id}
          moduleId={selection.id}
          open
          onOpenChange={close}
        />
      )}
    </div>
  );
}

export function ModulesPanel() {
  const scope = useModuleQueryScope();
  return <ProjectModulesPanel key={JSON.stringify(scope)} />;
}
