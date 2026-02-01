"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@ui/tooltip";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@ui/dropdown-menu";
import {
  Check,
  Folder,
  List,
  Loader2,
  MoreVertical,
  Pause,
  Pencil,
  Play,
  RefreshCw,
  Terminal,
  X,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import type { ProcessSource, ProcessStatus } from "./types";
import { ProcessStatusIndicator } from "./process-status-indicator";
import { ProcessLogsDialog } from "./process-logs-dialog";
import { useStartProcess, useStopProcess, useRestartProcess } from "@/lib/use-agent";

interface ProcessListProps {
  sources: ProcessSource[];
  statuses: Record<string, ProcessStatus>;
  onRemove: (id: string) => void;
  onToggleAutoStart: (id: string, autoStart: boolean) => void;
  onToggleEntrypoint: (id: string, useEntrypoint: boolean) => void;
  onClickAdd: () => void;
  _onClickSave: () => void;
  _isAdding: boolean;
}

export function ProcessList({ sources, statuses, onRemove, onToggleAutoStart: _onToggleAutoStart, onToggleEntrypoint: _onToggleEntrypoint, onClickAdd, _onClickSave, _isAdding }: ProcessListProps) {
  const [logsDialogOpen, setLogsDialogOpen] = useState(false);
  const [selectedProcess, setSelectedProcess] = useState<{ name: string; status?: string; isRunning?: boolean } | null>(null);
  const [actionInProgress, setActionInProgress] = useState<string | null>(null);

  const startProcess = useStartProcess();
  const stopProcess = useStopProcess();
  const restartProcess = useRestartProcess();

  const handleStart = async (name: string) => {
    setActionInProgress(name);
    try {
      const result = await startProcess.mutateAsync(name);
      if (result.success) {
        toast.success(`Started ${name}`);
      } else {
        toast.error(result.error || `Failed to start ${name}`);
      }
    } catch {
      toast.error(`Failed to start ${name}`);
    } finally {
      setActionInProgress(null);
    }
  };

  const handleStop = async (name: string) => {
    setActionInProgress(name);
    try {
      const result = await stopProcess.mutateAsync(name);
      if (result.success) {
        toast.success(`Stopped ${name}`);
      } else {
        toast.error(result.error || `Failed to stop ${name}`);
      }
    } catch {
      toast.error(`Failed to stop ${name}`);
    } finally {
      setActionInProgress(null);
    }
  };

  const handleRestart = async (name: string) => {
    setActionInProgress(name);
    try {
      const result = await restartProcess.mutateAsync(name);
      if (result.success) {
        toast.success(`Restarted ${name}`);
      } else {
        toast.error(result.error || `Failed to restart ${name}`);
      }
    } catch {
      toast.error(`Failed to restart ${name}`);
    } finally {
      setActionInProgress(null);
    }
  };

  const openLogs = (name: string, status?: ProcessStatus) => {
    setSelectedProcess({ name, status: status?.status, isRunning: status?.isRunning });
    setLogsDialogOpen(true);
  };

  if (sources.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium flex items-center gap-2">
            <List className="h-4 w-4" />
            Configured Processes
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="py-8 text-center text-muted-foreground">
            <p>No processes enabled yet.</p>
            <p className="text-sm mt-1">Select processes from the tabs above to add them.</p>
          </div>
        </CardContent>
      </Card>
    );
  }

  // Group by namespace
  const byNamespace = sources.reduce((acc, source) => {
    const ns = source.namespace ?? "default";
    if (!acc[ns]) acc[ns] = [];
    acc[ns].push(source);
    return acc;
  }, {} as Record<string, ProcessSource[]>);

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium flex items-center gap-2">
            <List className="h-4 w-4" />
            Configured Processes
            <Button variant="outline" size="sm" onClick={onClickAdd} className="ml-auto" data-icon="inline-start">
              <Pencil />
              Edit
            </Button>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {Object.entries(byNamespace).map(([namespace, nsProcesses]) => (
            <div key={namespace}>
              <div className="flex items-center gap-2 mb-2">
                <Badge variant="outline" className="text-xs">
                  {namespace}
                </Badge>
                <span className="text-xs text-muted-foreground">
                  {nsProcesses.length} process{nsProcesses.length !== 1 ? "es" : ""}
                </span>
              </div>
              <div className="space-y-2">
                {nsProcesses.map((source) => {
                  const status = statuses[source.name];
                  const isLoading = actionInProgress === source.name;
                  const isRunning = status?.isRunning ?? false;

                  return (
                    <div
                      key={source.id}
                      className="flex items-center gap-3 rounded-lg border p-3 bg-secondary/20"
                    >
                      <ProcessStatusIndicator status={status} />

                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-medium truncate">{source.name}</span>
                          <Badge variant="outline" className="text-xs capitalize">
                            {source.type}
                          </Badge>
                        </div>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <code className="text-xs text-muted-foreground truncate block max-w-[400px]">
                              {source.command}
                            </code>
                          </TooltipTrigger>
                          <TooltipContent side="bottom" className="max-w-lg">
                            <code className="text-xs break-all">{source.command}</code>
                          </TooltipContent>
                        </Tooltip>
                      </div>

                      {source.workingDir && (
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <div className="flex items-center gap-1 text-xs text-muted-foreground">
                              <Folder className="h-3 w-3" />
                              <span className="truncate max-w-[100px]">{source.workingDir}</span>
                            </div>
                          </TooltipTrigger>
                          <TooltipContent>
                            <code>{source.workingDir}</code>
                          </TooltipContent>
                        </Tooltip>
                      )}

                      {/* Process control buttons */}
                      <div className="flex items-center gap-1">
                        {isLoading ? (
                          <Button variant="ghost" size="icon" className="h-8 w-8" disabled>
                            <Loader2 className="h-4 w-4 animate-spin" />
                          </Button>
                        ) : isRunning ? (
                          <>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  className="h-8 w-8 text-muted-foreground hover:text-red-500"
                                  onClick={() => handleStop(source.name)}
                                >
                                  <Pause className="h-4 w-4" />
                                </Button>
                              </TooltipTrigger>
                              <TooltipContent>Stop process</TooltipContent>
                            </Tooltip>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  className="h-8 w-8 text-muted-foreground hover:text-accent"
                                  onClick={() => handleRestart(source.name)}
                                >
                                  <RefreshCw className="h-4 w-4" />
                                </Button>
                              </TooltipTrigger>
                              <TooltipContent>Restart process</TooltipContent>
                            </Tooltip>
                          </>
                        ) : (
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8 text-muted-foreground hover:text-emerald-500"
                                onClick={() => handleStart(source.name)}
                              >
                                <Play className="h-4 w-4" />
                              </Button>
                            </TooltipTrigger>
                            <TooltipContent>Start process</TooltipContent>
                          </Tooltip>
                        )}

                        <Tooltip>
                          <TooltipTrigger asChild>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-muted-foreground hover:text-accent"
                              onClick={() => openLogs(source.name, status)}
                            >
                              <Terminal className="h-4 w-4" />
                            </Button>
                          </TooltipTrigger>
                          <TooltipContent>View logs</TooltipContent>
                        </Tooltip>
                      </div>

                      {/* More options dropdown */}
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button variant="ghost" size="icon" className="h-8 w-8">
                            <MoreVertical className="h-4 w-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem onClick={() => openLogs(source.name, status)}>
                            <Terminal className="mr-2 h-4 w-4" />
                            View Logs
                          </DropdownMenuItem>
                          {isRunning ? (
                            <>
                              <DropdownMenuItem onClick={() => handleStop(source.name)}>
                                <Pause className="mr-2 h-4 w-4" />
                                Stop
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => handleRestart(source.name)}>
                                <RefreshCw className="mr-2 h-4 w-4" />
                                Restart
                              </DropdownMenuItem>
                            </>
                          ) : (
                            <DropdownMenuItem onClick={() => handleStart(source.name)}>
                              <Play className="mr-2 h-4 w-4" />
                              Start
                            </DropdownMenuItem>
                          )}
                          <DropdownMenuItem
                            className="text-destructive"
                            onClick={() => onRemove(source.id)}
                          >
                            <X className="mr-2 h-4 w-4" />
                            Remove
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Logs Dialog */}
      {selectedProcess && (
        <ProcessLogsDialog
          open={logsDialogOpen}
          onOpenChange={setLogsDialogOpen}
          processName={selectedProcess.name}
          processStatus={selectedProcess.status}
          isRunning={selectedProcess.isRunning}
        />
      )}
    </>
  );
}
