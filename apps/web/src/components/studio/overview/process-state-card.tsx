"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Button } from "@ui/button";
import { Badge } from "@ui/badge";
import {
  Activity,
  CheckCircle2,
  ChevronRight,
  Cpu,
  Loader2,
  PlayCircle,
  RefreshCw,
  Square,
  Terminal,
  XCircle,
} from "lucide-react";
import { Link } from "@tanstack/react-router";
import { useProcesses, useProcessComposeProjectState } from "@/lib/use-agent";
import { useAgentContext } from "@/lib/agent-provider";
import { cn } from "@/lib/utils";

/**
 * Card showing detailed process-compose state on the overview page.
 * Shows running/total processes, memory usage, and quick access to process logs.
 */
export function ProcessStateCard() {
  const { isConnected } = useAgentContext();
  const { data: processes, isLoading: processesLoading, refetch: refetchProcesses } = useProcesses();
  const { data: projectState, isLoading: stateLoading } = useProcessComposeProjectState();

  const isLoading = processesLoading || stateLoading;
  const isAvailable = processes?.available ?? projectState?.available ?? false;

  // Count running vs total processes
  const runningCount = processes?.processes?.filter(p => p.isRunning)?.length ?? 0;
  const totalCount = processes?.processes?.length ?? 0;

  // Group processes by namespace
  type ProcessInfoType = NonNullable<typeof processes>["processes"][number];
  const processesByNamespace = (processes?.processes ?? []).reduce((acc, p) => {
    const ns = p.namespace || "default";
    if (!acc[ns]) acc[ns] = [];
    acc[ns].push(p);
    return acc;
  }, {} as Record<string, ProcessInfoType[]>);

  // Safely access state properties
  const stateVersion = projectState?.state?.version as string | undefined;
  const memoryState = projectState?.state?.memoryState as { allocated?: number; total?: number } | undefined;

  // Format memory size
  const formatBytes = (bytes?: number) => {
    if (!bytes) return "—";
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  };

  if (!isConnected) {
    return (
      <Card className="opacity-50">
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base font-medium">
            <Activity className="h-4 w-4 text-muted-foreground" />
            Process Compose
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">Connect to agent to view processes</p>
        </CardContent>
      </Card>
    );
  }

  if (!isAvailable) {
    return (
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base font-medium">
            <Activity className="h-4 w-4 text-muted-foreground" />
            Process Compose
            <Badge variant="outline" className="ml-auto text-xs">Not Running</Badge>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="py-4 text-center">
            <Terminal className="mx-auto h-8 w-8 text-muted-foreground mb-2" />
            <p className="text-sm text-muted-foreground">Process compose is not running</p>
            <p className="text-xs text-muted-foreground mt-1">
              Run <code className="rounded bg-muted px-1">dev</code> in your terminal to start
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-3">
        <CardTitle className="flex items-center gap-2 text-base font-medium">
          <Activity className="h-4 w-4 text-accent" />
          Process Compose
          {stateVersion && (
            <span className="text-xs font-normal text-muted-foreground">
              v{stateVersion}
            </span>
          )}
        </CardTitle>
        <div className="flex items-center gap-2">
          <Badge 
            variant={runningCount === totalCount ? "default" : "secondary"}
            className={cn(
              "text-xs",
              runningCount === totalCount && "bg-emerald-500/10 text-emerald-500 border-emerald-500/20"
            )}
          >
            {runningCount}/{totalCount} Running
          </Badge>
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            onClick={() => refetchProcesses()}
            disabled={isLoading}
          >
            <RefreshCw className={cn("h-4 w-4", isLoading && "animate-spin")} />
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="flex items-center justify-center py-6">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <div className="space-y-4">
            {/* Memory stats if available */}
            {memoryState && (
              <div className="flex items-center gap-4 p-3 rounded-lg bg-secondary/30 border border-border">
                <Cpu className="h-4 w-4 text-muted-foreground" />
                <div className="text-sm">
                  <span className="text-muted-foreground">Memory: </span>
                  <span className="font-medium">{formatBytes(memoryState.allocated)}</span>
                  <span className="text-muted-foreground"> / </span>
                  <span className="text-muted-foreground">{formatBytes(memoryState.total)}</span>
                </div>
              </div>
            )}

            {/* Process list grouped by namespace */}
            <div className="space-y-3">
              {Object.entries(processesByNamespace).map(([namespace, procs]) => (
                <div key={namespace}>
                  <div className="flex items-center gap-2 mb-2">
                    <span className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                      {namespace}
                    </span>
                    <div className="flex-1 h-px bg-border" />
                  </div>
                  <div className="grid gap-2">
                    {procs.slice(0, 5).map((proc) => (
                      <Link
                        key={proc.name}
                        to="/studio/processes"
                        className="flex items-center justify-between p-2 rounded-lg hover:bg-secondary/50 transition-colors group"
                      >
                        <div className="flex items-center gap-2">
                          {proc.isRunning ? (
                            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
                          ) : proc.status === "Disabled" ? (
                            <Square className="h-4 w-4 text-muted-foreground" />
                          ) : (
                            <XCircle className="h-4 w-4 text-red-500" />
                          )}
                          <span className="text-sm font-medium">{proc.name}</span>
                          {proc.pid && proc.isRunning && (
                            <span className="text-xs text-muted-foreground">
                              PID {proc.pid}
                            </span>
                          )}
                        </div>
                        <div className="flex items-center gap-2">
                          <Badge
                            variant="outline"
                            className={cn(
                              "text-xs",
                              proc.isRunning && "border-emerald-500/30 text-emerald-500",
                              !proc.isRunning && proc.status !== "Disabled" && "border-red-500/30 text-red-500"
                            )}
                          >
                            {proc.status}
                          </Badge>
                          <ChevronRight className="h-4 w-4 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                        </div>
                      </Link>
                    ))}
                    {procs.length > 5 && (
                      <Link
                        to="/studio/processes"
                        className="text-xs text-muted-foreground hover:text-foreground text-center py-1"
                      >
                        +{procs.length - 5} more processes
                      </Link>
                    )}
                  </div>
                </div>
              ))}
            </div>

            {/* Link to processes page */}
            <Link to="/studio/processes">
              <Button variant="outline" size="sm" className="w-full">
                <PlayCircle className="mr-2 h-4 w-4" />
                View All Processes
              </Button>
            </Link>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
