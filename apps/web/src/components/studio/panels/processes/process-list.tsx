"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Checkbox } from "@ui/checkbox";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@ui/tooltip";
import { Folder, List, X } from "lucide-react";
import type { ProcessSource, ProcessStatus } from "./types";
import { ProcessStatusIndicator } from "./process-status-indicator";

interface ProcessListProps {
  sources: ProcessSource[];
  statuses: Record<string, ProcessStatus>;
  onRemove: (id: string) => void;
  onToggleAutoStart: (id: string, autoStart: boolean) => void;
  onToggleEntrypoint: (id: string, useEntrypoint: boolean) => void;
}

export function ProcessList({ sources, statuses, onRemove, onToggleAutoStart, onToggleEntrypoint }: ProcessListProps) {
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
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-medium flex items-center gap-2">
          <List className="h-4 w-4" />
          Configured Processes
          <Badge variant="secondary" className="ml-auto">
            {sources.length}
          </Badge>
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

                    <Tooltip>
                      <TooltipTrigger asChild>
                        <div className="flex items-center gap-2">
                          <Checkbox
                            id={`autostart-${source.id}`}
                            checked={source.autoStart}
                            onCheckedChange={(checked) => onToggleAutoStart(source.id, !!checked)}
                          />
                          <label
                            htmlFor={`autostart-${source.id}`}
                            className="text-xs text-muted-foreground cursor-pointer"
                          >
                            Auto
                          </label>
                        </div>
                      </TooltipTrigger>
                      <TooltipContent>
                        {source.autoStart
                          ? "Process starts automatically with 'dev'"
                          : "Process shows in TUI but doesn't auto-start"}
                      </TooltipContent>
                    </Tooltip>

                    {source.type === "app" && (
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <div className="flex items-center gap-2">
                            <Checkbox
                              id={`entrypoint-${source.id}`}
                              checked={source.useEntrypoint}
                              onCheckedChange={(checked) => onToggleEntrypoint(source.id, !!checked)}
                            />
                            <label
                              htmlFor={`entrypoint-${source.id}`}
                              className="text-xs text-muted-foreground cursor-pointer"
                            >
                              Entry
                            </label>
                          </div>
                        </TooltipTrigger>
                        <TooltipContent>
                          {source.useEntrypoint
                            ? "Uses entrypoint script (loads env vars, secrets)"
                            : "Runs command directly without entrypoint"}
                        </TooltipContent>
                      </Tooltip>
                    )}

                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-destructive"
                      onClick={() => onRemove(source.id)}
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
