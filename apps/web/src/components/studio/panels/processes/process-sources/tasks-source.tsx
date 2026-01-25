"use client";

import { Badge } from "@ui/badge";
import { Checkbox } from "@ui/checkbox";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@ui/tooltip";
import { Package, Play } from "lucide-react";
import type { SourceTabProps } from "../types";
import { ProcessStatusIndicator } from "../process-status-indicator";

export function TasksSource({ sources, statuses, onToggle }: SourceTabProps) {
  if (sources.length === 0) {
    return (
      <div className="py-8 text-center">
        <Play className="mx-auto h-12 w-12 text-muted-foreground/50" />
        <p className="mt-2 text-muted-foreground">
          No tasks found from turbo.json
        </p>
        <p className="mt-1 text-sm text-muted-foreground/70">
          Tasks are discovered from your turbo configuration
        </p>
      </div>
    );
  }

  // Group tasks by package for better organization
  const tasksByPackage = sources.reduce((acc, source) => {
    const pkg = source.packageFilter ?? "root";
    if (!acc[pkg]) acc[pkg] = [];
    acc[pkg].push(source);
    return acc;
  }, {} as Record<string, typeof sources>);

  return (
    <div className="space-y-4">
      {Object.entries(tasksByPackage).map(([packageName, tasks]) => (
        <div key={packageName}>
          <div className="flex items-center gap-2 mb-2">
            <Package className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm font-medium text-muted-foreground">
              {packageName}
            </span>
          </div>
          <div className="space-y-2 pl-6">
            {tasks.map((source) => {
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
                      <code className="rounded bg-secondary px-2 py-0.5 text-sm font-medium">
                        {source.taskName}
                      </code>
                      <Badge variant="outline" className="text-xs">
                        -F {source.packageFilter}
                      </Badge>
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
                </div>
              );
            })}
          </div>
        </div>
      ))}
      
      <div className="mt-4 rounded-lg bg-secondary/30 p-3 text-xs text-muted-foreground">
        Tasks use Turborepo&apos;s <code className="bg-secondary px-1 rounded">-F</code> flag to filter which package to run on.
        Select tasks to run them as long-running processes.
      </div>
    </div>
  );
}
