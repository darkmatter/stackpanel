"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@ui/tooltip";
import {
  AppWindow,
  ChevronDown,
  ChevronRight,
  Eye,
  FileCode,
  Loader2,
  Play,
  Plus,
  Save,
  Search,
  Settings,
  Terminal,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import { useAgentClient } from "@/lib/agent-provider";
import { useRebuildShell } from "@/lib/use-agent";
import { PanelHeader } from "../shared/panel-header";
import { useProcessSources, useProcessConfig } from "./hooks";
import { AppsSource } from "./process-sources/apps-source";
import { ScriptsSource } from "./process-sources/scripts-source";
import { TasksSource } from "./process-sources/tasks-source";
import { CustomSource } from "./process-sources/custom-source";
import { ProcessList } from "./process-list";
import { ProcessSettings } from "./process-settings";
import { NixOutputDialog } from "./nix-output-dialog";
import { YamlPreviewDialog } from "./yaml-preview-dialog";
import type { SourceTab } from "./types";

const CONFIG_PATH = ".stackpanel/gen/process-compose.nix";

export function ProcessesPanel() {
  // Fetch data from sources
  const {
    appSources,
    scriptSources,
    taskSources,
    settings: initialSettings,
    statuses,
    isLoading,
    error,
    refetch,
  } = useProcessSources();

  // Manage local config state
  const {
    sources,
    customSources,
    settings,
    activeTab,
    searchQuery,
    setActiveTab,
    setSearchQuery,
    toggleSource,
    toggleAutoStart,
    toggleEntrypoint,
    updateSettings,
    addCustomSource,
    removeCustomSource,
    updateCustomSource,
    generateNix,
    generateYaml,
    getEnabledSources,
  } = useProcessConfig({
    initialSources: [...appSources, ...scriptSources, ...taskSources],
    initialSettings,
  });

  // Agent client for writing files
  const client = useAgentClient();

  // Rebuild shell hook
  const { rebuild, isRebuilding } = useRebuildShell();

  // Dialog states
  const [nixDialogOpen, setNixDialogOpen] = useState(false);
  const [yamlDialogOpen, setYamlDialogOpen] = useState(false);
  const [settingsExpanded, setSettingsExpanded] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  // Handle save and rebuild
  const handleSaveAndRebuild = async () => {
    if (!client) {
      toast.error("Not connected to agent");
      return;
    }

    setIsSaving(true);
    try {
      // Generate the Nix config
      const nixConfig = generateNix("partial");
      
      // Write to file
      toast.info(`Writing config to ${CONFIG_PATH}...`);
      await client.writeFile(CONFIG_PATH, nixConfig.content);
      
      // Rebuild the shell
      toast.info("Rebuilding devshell...");
      const result = await rebuild("devshell");
      
      if (result?.success) {
        toast.success("Configuration saved and devshell rebuilt!", { duration: 3000 });
        refetch();
      } else {
        toast.error("Devshell rebuild failed. Check the terminal for details.", { duration: 5000 });
      }
    } catch (err) {
      toast.error(`Failed to save: ${err instanceof Error ? err.message : "Unknown error"}`, { duration: 5000 });
    } finally {
      setIsSaving(false);
    }
  };

  // Handle run dev command
  const handleRunDev = () => {
    toast.info(
      <div className="space-y-1">
        <p className="font-medium">Run in your terminal:</p>
        <code className="block bg-secondary px-2 py-1 rounded text-xs">
          {settings.commandName}
        </code>
      </div>,
      { duration: 5000 }
    );
  };

  // Filter sources by search query
  const filterSources = (sourcesToFilter: typeof sources) => {
    if (!searchQuery) return sourcesToFilter;
    const query = searchQuery.toLowerCase();
    return sourcesToFilter.filter(
      (s) =>
        s.name.toLowerCase().includes(query) ||
        s.command.toLowerCase().includes(query)
    );
  };

  // Get filtered sources for each tab
  const filteredAppSources = filterSources(sources.filter((s) => s.type === "app"));
  const filteredScriptSources = filterSources(sources.filter((s) => s.type === "script"));
  const filteredTaskSources = filterSources(sources.filter((s) => s.type === "task"));
  const filteredCustomSources = filterSources(customSources);

  // Get enabled count for each tab
  const enabledCounts = {
    apps: sources.filter((s) => s.type === "app" && s.enabled).length,
    scripts: sources.filter((s) => s.type === "script" && s.enabled).length,
    tasks: sources.filter((s) => s.type === "task" && s.enabled).length,
    custom: customSources.filter((s) => s.enabled).length,
  };

  const totalEnabled = Object.values(enabledCounts).reduce((a, b) => a + b, 0);
  const isWorking = isSaving || isRebuilding;

  if (isLoading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="border-destructive/50">
        <CardContent className="py-6">
          <p className="text-center text-destructive">
            Failed to load process sources: {error?.message ?? "Unknown error"}
          </p>
          <div className="mt-4 flex justify-center">
            <Button variant="outline" onClick={refetch}>
              Retry
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <TooltipProvider>
      <div className="space-y-6">
        {/* Header */}
        <PanelHeader
          title="Process Compose"
          description={`Configure development processes. ${totalEnabled} process${totalEnabled !== 1 ? "es" : ""} enabled.`}
          guideKey="tasks"
          actions={
            <div className="flex gap-2">
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button variant="outline" size="sm" onClick={() => setYamlDialogOpen(true)}>
                    <Eye className="mr-2 h-4 w-4" />
                    Preview
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Preview generated YAML and Nix config</TooltipContent>
              </Tooltip>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button 
                    variant="outline" 
                    size="sm" 
                    onClick={handleSaveAndRebuild}
                    disabled={isWorking}
                  >
                    {isWorking ? (
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    ) : (
                      <Save className="mr-2 h-4 w-4" />
                    )}
                    {isSaving ? "Saving..." : isRebuilding ? "Rebuilding..." : "Save & Rebuild"}
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  Save config to {CONFIG_PATH} and rebuild devshell
                </TooltipContent>
              </Tooltip>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button 
                    className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"
                    onClick={handleRunDev}
                  >
                    <Terminal className="h-4 w-4" />
                    Run {settings.commandName}
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  <code>$ {settings.commandName}</code>
                </TooltipContent>
              </Tooltip>
            </div>
          }
        />

        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search processes..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9"
          />
        </div>

        {/* Source Tabs */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base font-medium">Add Processes</CardTitle>
          </CardHeader>
          <CardContent>
            <Tabs
              value={activeTab}
              onValueChange={(v) => setActiveTab(v as SourceTab)}
            >
              <TabsList className="grid w-full grid-cols-4">
                <TabsTrigger value="apps" className="gap-2">
                  <AppWindow className="h-4 w-4" />
                  Apps
                  {enabledCounts.apps > 0 && (
                    <Badge variant="secondary" className="ml-1">
                      {enabledCounts.apps}
                    </Badge>
                  )}
                </TabsTrigger>
                <TabsTrigger value="scripts" className="gap-2">
                  <FileCode className="h-4 w-4" />
                  Scripts
                  {enabledCounts.scripts > 0 && (
                    <Badge variant="secondary" className="ml-1">
                      {enabledCounts.scripts}
                    </Badge>
                  )}
                </TabsTrigger>
                <TabsTrigger value="tasks" className="gap-2">
                  <Play className="h-4 w-4" />
                  Tasks
                  {enabledCounts.tasks > 0 && (
                    <Badge variant="secondary" className="ml-1">
                      {enabledCounts.tasks}
                    </Badge>
                  )}
                </TabsTrigger>
                <TabsTrigger value="custom" className="gap-2">
                  <Plus className="h-4 w-4" />
                  Custom
                  {enabledCounts.custom > 0 && (
                    <Badge variant="secondary" className="ml-1">
                      {enabledCounts.custom}
                    </Badge>
                  )}
                </TabsTrigger>
              </TabsList>

              <TabsContent value="apps" className="mt-4">
                <AppsSource
                  sources={filteredAppSources}
                  statuses={statuses}
                  onToggle={toggleSource}
                />
              </TabsContent>

              <TabsContent value="scripts" className="mt-4">
                <ScriptsSource
                  sources={filteredScriptSources}
                  statuses={statuses}
                  onToggle={toggleSource}
                />
              </TabsContent>

              <TabsContent value="tasks" className="mt-4">
                <TasksSource
                  sources={filteredTaskSources}
                  statuses={statuses}
                  onToggle={toggleSource}
                />
              </TabsContent>

              <TabsContent value="custom" className="mt-4">
                <CustomSource
                  sources={filteredCustomSources}
                  statuses={statuses}
                  onToggle={toggleSource}
                  onAdd={addCustomSource}
                  onRemove={removeCustomSource}
                  onUpdate={updateCustomSource}
                />
              </TabsContent>
            </Tabs>
          </CardContent>
        </Card>

        {/* Configured Processes List */}
        <ProcessList
          sources={getEnabledSources()}
          statuses={statuses}
          onRemove={(id) => {
            // Check if custom, then remove; otherwise just disable
            const source = customSources.find((s) => s.id === id);
            if (source) {
              removeCustomSource(id);
            } else {
              toggleSource(id, false);
            }
          }}
          onToggleAutoStart={toggleAutoStart}
          onToggleEntrypoint={toggleEntrypoint}
        />

        {/* Settings */}
        <Card>
          <CardHeader
            className="cursor-pointer"
            onClick={() => setSettingsExpanded(!settingsExpanded)}
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Settings className="h-4 w-4" />
                <CardTitle className="text-base font-medium">Settings</CardTitle>
              </div>
              {settingsExpanded ? (
                <ChevronDown className="h-4 w-4 text-muted-foreground" />
              ) : (
                <ChevronRight className="h-4 w-4 text-muted-foreground" />
              )}
            </div>
          </CardHeader>
          {settingsExpanded && (
            <CardContent>
              <ProcessSettings
                settings={settings}
                onUpdate={updateSettings}
              />
            </CardContent>
          )}
        </Card>

        {/* Info Card */}
        <Card className="border-accent/30 bg-accent/5">
          <CardContent className="py-4">
            <div className="flex items-start gap-3">
              <Terminal className="mt-0.5 h-5 w-5 text-accent" />
              <div className="text-sm">
                <p className="font-medium text-foreground">
                  Run all processes with a single command
                </p>
                <p className="mt-1 text-muted-foreground">
                  Configure your processes above, then click <strong>Save & Rebuild</strong> to apply changes.
                  Once rebuilt, run <code className="rounded bg-secondary px-1 py-0.5 text-xs">{settings.commandName}</code> in your terminal.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Dialogs */}
        <NixOutputDialog
          open={nixDialogOpen}
          onOpenChange={setNixDialogOpen}
          generateNix={generateNix}
        />
        <YamlPreviewDialog
          open={yamlDialogOpen}
          onOpenChange={setYamlDialogOpen}
          yaml={generateYaml()}
          onShowNix={() => {
            setYamlDialogOpen(false);
            setNixDialogOpen(true);
          }}
        />
      </div>
    </TooltipProvider>
  );
}
