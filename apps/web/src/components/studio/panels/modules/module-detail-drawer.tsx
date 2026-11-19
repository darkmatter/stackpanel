import type { Module } from "@stackpanel/proto/agent/v1/module";
import { Link } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@ui/sheet";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import {
  AlertCircle,
  BookOpen,
  ExternalLink,
  FolderGit,
  Layers,
  Loader2,
  Package,
  Search,
  Settings,
} from "lucide-react";
import { useState } from "react";
import { ModuleMarkdown } from "../shared/module-markdown";
import { PanelActionBar } from "../shared/panel-action-bar";
import { StudioPanel } from "../shared/studio-panel";
import { unplacedModuleActions } from "../shared/unplaced-module-actions";
import { useStudioPanels } from "../shared/use-studio-panels";
import { ModuleConfigForm } from "./module-config-form";
import { ModuleFeatures } from "./module-features";
import { ModuleEnableControl, ShellRebuildPrompt } from "./module-lifecycle-controls";
import { ModuleOutputsSection } from "./module-outputs";
import { getCategoryLabel, getSourceLabel } from "./module-labels";
import { useModule, useRegistryModules } from "./use-modules";

interface ModuleDetailDrawerProps {
  moduleId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onManageRegistry?: (slug: string) => void;
}

function ModuleWorkspace({ module }: { module: Module }) {
  const { catalog, panels, isLoading, error } = useStudioPanels();
  const belongsHere = (panel: (typeof panels)[number]) =>
    panel.module === module.id && panel.slot === "module";
  const mounted = panels.filter(belongsHere);
  const actions = unplacedModuleActions(Object.keys(module.actions), catalog.filter(belongsHere));
  return (
    <div className="space-y-4">
      {actions.length > 0 && (
        <section className="space-y-2">
          <h4 className="text-sm font-medium">Actions</h4>
          <PanelActionBar moduleId={module.id} actionIds={actions} />
        </section>
      )}
      {error ? (
        <p role="alert" className="text-sm text-destructive">
          Failed to load module panels: {error.message}
        </p>
      ) : isLoading ? (
        <p role="status" className="text-sm text-muted-foreground">
          Loading module panels…
        </p>
      ) : (
        mounted.map((panel) => <StudioPanel key={panel.id} panel={panel} />)
      )}
    </div>
  );
}

function RegistryManagement({ id, onManage }: { id: string; onManage: (slug: string) => void }) {
  const catalog = useRegistryModules();
  if (catalog.error)
    return (
      <div className="space-y-2">
        <p role="alert" className="text-sm text-destructive">
          Could not check registry installation: {catalog.error.message}
        </p>
        <Button
          variant="outline"
          size="sm"
          disabled={catalog.isFetching}
          onClick={() => void catalog.refetch()}
        >
          Retry registry lookup
        </Button>
      </div>
    );
  const entry = catalog.data?.modules.find((item) => item.slug === id && item.installed);
  if (!entry) return null;
  return (
    <Button variant="outline" size="sm" onClick={() => onManage(entry.slug)}>
      <FolderGit className="mr-2 h-4 w-4" />
      Manage registry installation
    </Button>
  );
}

function ModuleOverview({
  module,
  onManageRegistry,
}: {
  module: Module;
  onManageRegistry?: (slug: string) => void;
}) {
  const metadata = [
    ["Category", getCategoryLabel(module.meta?.category)],
    ["Source", getSourceLabel(module.source?.type)],
    ["Flake input", module.source?.flakeInput],
    ["Path", module.source?.path],
    ["Ref", module.source?.ref],
    ["Version", module.meta?.version],
    ["Author", module.meta?.author],
    ["Priority", String(module.priority)],
  ];
  return (
    <div className="space-y-6">
      {module.meta?.description && (
        <section>
          <h4 className="mb-2 text-sm font-medium">Description</h4>
          <p className="text-sm text-muted-foreground">{module.meta.description}</p>
        </section>
      )}
      {module.enabled ? (
        <ModuleWorkspace module={module} />
      ) : (
        <p className="rounded-md border bg-muted/30 p-3 text-sm text-muted-foreground">
          This module is disabled. Review the enable plan to see what it would add to your project.
        </p>
      )}
      {module.missingFlakeInputs.length > 0 && (
        <section className="rounded-md border p-3">
          <h4 className="text-sm font-medium">Missing flake inputs</h4>
          <ul className="mt-2 space-y-1 text-xs text-muted-foreground">
            {module.missingFlakeInputs.map((input) => (
              <li key={input.name}>
                <code>{input.name}</code> — {input.url}
              </li>
            ))}
          </ul>
        </section>
      )}
      <ModuleFeatures values={module.features} />
      <section>
        <h4 className="mb-2 text-sm font-medium">Details</h4>
        <dl className="space-y-2 text-sm">
          {metadata.map(
            ([label, value]) =>
              value && (
                <div key={label} className="flex justify-between gap-4">
                  <dt className="text-muted-foreground">{label}</dt>
                  <dd className="break-all text-right">{value}</dd>
                </div>
              ),
          )}
        </dl>
      </section>
      {Object.entries({
        Tags: module.tags,
        Requires: module.requires,
        Conflicts: module.conflicts,
      }).map(
        ([label, values]) =>
          values.length > 0 && (
            <section key={label}>
              <h4 className="mb-2 text-sm font-medium">{label}</h4>
              <div className="flex flex-wrap gap-1">
                {values.map((value) => (
                  <Badge key={value} variant="outline">
                    {value}
                  </Badge>
                ))}
              </div>
            </section>
          ),
      )}
      <div className="flex flex-wrap gap-2">
        {module.meta?.homepage && /^https?:\/\//i.test(module.meta.homepage) && (
          <Button variant="outline" size="sm" asChild>
            <a href={module.meta.homepage} target="_blank" rel="noopener noreferrer">
              <ExternalLink className="mr-2 h-4 w-4" />
              Homepage
            </a>
          </Button>
        )}
        <Button variant="outline" size="sm" asChild>
          <Link to="/studio/inspector" search={{ contributor: module.id }}>
            <Search className="mr-2 h-4 w-4" />
            View in Inspector
          </Link>
        </Button>
        {onManageRegistry && <RegistryManagement id={module.id} onManage={onManageRegistry} />}
      </div>
    </div>
  );
}

function ModuleDetail({
  module,
  onManageRegistry,
}: {
  module: Module;
  onManageRegistry?: (slug: string) => void;
}) {
  const [change, setChange] = useState({ count: 0, message: "" });
  const [tab, setTab] = useState("overview");
  const onChanged = (message: string) =>
    setChange((previous) => ({ count: previous.count + 1, message }));
  return (
    <>
      <SheetHeader>
        <div className="flex items-center justify-between gap-2 pr-8">
          <div className="min-w-0">
            <SheetTitle className="flex flex-wrap items-center gap-2">
              {module.meta?.name || module.id}
              {module.source?.type === "builtin" && <Badge variant="secondary">Builtin</Badge>}
            </SheetTitle>
            <SheetDescription>
              {module.id} · {module.enabled ? "Enabled" : "Disabled"}
            </SheetDescription>
          </div>
          <ModuleEnableControl
            moduleId={module.id}
            enabled={module.enabled}
            onChanged={onChanged}
          />
        </div>
      </SheetHeader>
      {change.count > 0 && <ShellRebuildPrompt key={change.count} message={change.message} />}
      <Tabs value={tab} onValueChange={setTab} className="mt-6">
        <TabsList className="grid w-full grid-cols-4">
          <TabsTrigger value="overview">
            <Package className="hidden h-3.5 w-3.5 sm:block" />
            Overview
          </TabsTrigger>
          <TabsTrigger value="config">
            <Settings className="hidden h-3.5 w-3.5 sm:block" />
            Config
          </TabsTrigger>
          <TabsTrigger value="outputs">
            <Layers className="hidden h-3.5 w-3.5 sm:block" />
            Outputs
          </TabsTrigger>
          <TabsTrigger value="docs">
            <BookOpen className="hidden h-3.5 w-3.5 sm:block" />
            Docs
          </TabsTrigger>
        </TabsList>
        <TabsContent value="overview" className="mt-4">
          <ModuleOverview module={module} onManageRegistry={onManageRegistry} />
        </TabsContent>
        <TabsContent value="config" forceMount hidden={tab !== "config"} className="mt-4">
          {module.settings ? (
            <ModuleConfigForm
              key={module.configSchema}
              moduleId={module.id}
              settings={module.settings}
              schema={module.configSchema}
              onChanged={onChanged}
            />
          ) : (
            <p role="alert">The agent returned no module settings. Refresh before editing.</p>
          )}
        </TabsContent>
        <TabsContent value="outputs" className="mt-4">
          <ModuleOutputsSection moduleId={module.id} />
        </TabsContent>
        <TabsContent value="docs" className="mt-4">
          {module.readmeContent?.trim() ? (
            <ModuleMarkdown>{module.readmeContent}</ModuleMarkdown>
          ) : (
            <p className="text-sm text-muted-foreground">This module does not provide a README.</p>
          )}
        </TabsContent>
      </Tabs>
    </>
  );
}

export function ModuleDetailDrawer({
  moduleId,
  open,
  onOpenChange,
  onManageRegistry,
}: ModuleDetailDrawerProps) {
  const detail = useModule(moduleId, { enabled: open });
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto px-4 pb-6 sm:max-w-lg">
        {detail.error ? (
          <div className="flex h-full flex-col items-center justify-center gap-4">
            <AlertCircle className="h-10 w-10 text-destructive" />
            <SheetTitle>Module unavailable</SheetTitle>
            <SheetDescription role="alert">
              Failed to load {moduleId}: {detail.error.message}
            </SheetDescription>
            <Button
              variant="outline"
              disabled={detail.isFetching}
              onClick={() => void detail.refetch()}
            >
              Try again
            </Button>
          </div>
        ) : detail.data ? (
          <ModuleDetail
            key={moduleId}
            module={detail.data.module}
            onManageRegistry={onManageRegistry}
          />
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-2">
            <SheetTitle>Module details</SheetTitle>
            <SheetDescription role="status">Loading {moduleId}…</SheetDescription>
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}
