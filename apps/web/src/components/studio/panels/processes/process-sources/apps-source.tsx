"use client";

import { Badge } from "@ui/badge";
import { Checkbox } from "@ui/checkbox";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@ui/tooltip";
import { AppWindow, Folder } from "lucide-react";
import type { SourceTabProps } from "../types";
import { ProcessStatusIndicator } from "../process-status-indicator";

export function AppsSource({ sources, statuses, onToggle }: SourceTabProps) {
  if (sources.length === 0) {
    return (
      <div className="py-8 text-center">
        <AppWindow className="mx-auto h-12 w-12 text-muted-foreground/50" />
        <p className="mt-2 text-muted-foreground">
          No apps found in your project
        </p>
        <p className="mt-1 text-sm text-muted-foreground/70">
          Define apps in <code className="rounded bg-secondary px-1 py-0.5">stackpanel.apps</code>
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {sources.map((source) => {
        const status = statuses[source.name];
        return (
          <div
            key={source.id}
            className="flex items-center gap-3 rounded-lg border p-3 hover:bg-secondary/30"
          >
            <Checkbox
              checked={source.enabled}
              onCheckedChange={(checked) => onToggle(source.id, !!checked)}
            />
            
            <ProcessStatusIndicator status={status} />
            
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="font-medium truncate">{source.name}</span>
                {source.namespace && (
                  <Badge variant="outline" className="text-xs">
                    {source.namespace}
                  </Badge>
                )}
              </div>
              <Tooltip>
                <TooltipTrigger asChild>
                  <code className="text-xs text-muted-foreground truncate block">
                    {source.command}
                  </code>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="max-w-md">
                  <code className="text-xs">{source.command}</code>
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
          </div>
        );
      })}
    </div>
  );
}
