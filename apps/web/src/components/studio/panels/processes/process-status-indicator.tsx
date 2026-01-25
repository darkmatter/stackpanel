"use client";

import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@ui/tooltip";
import { cn } from "@/lib/utils";
import type { ProcessStatus, ProcessStatusValue } from "./types";

interface ProcessStatusIndicatorProps {
  status?: ProcessStatus;
  className?: string;
}

const STATUS_CONFIG: Record<ProcessStatusValue, { color: string; label: string }> = {
  Running: { color: "bg-emerald-500", label: "Running" },
  Completed: { color: "bg-blue-500", label: "Completed" },
  Pending: { color: "bg-yellow-500", label: "Pending" },
  Failed: { color: "bg-red-500", label: "Failed" },
  Stopping: { color: "bg-orange-500", label: "Stopping" },
  Disabled: { color: "bg-gray-400", label: "Disabled" },
  Skipped: { color: "bg-gray-400", label: "Skipped" },
  Foreground: { color: "bg-emerald-500", label: "Foreground" },
  Launching: { color: "bg-yellow-500", label: "Launching" },
  Restarting: { color: "bg-yellow-500", label: "Restarting" },
  Terminated: { color: "bg-gray-500", label: "Terminated" },
};

export function ProcessStatusIndicator({ status, className }: ProcessStatusIndicatorProps) {
  // No status means not configured / not running
  if (!status) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>
          <div
            className={cn(
              "h-2.5 w-2.5 rounded-full bg-gray-300 dark:bg-gray-600",
              className
            )}
          />
        </TooltipTrigger>
        <TooltipContent>Not running</TooltipContent>
      </Tooltip>
    );
  }

  const config = STATUS_CONFIG[status.status] ?? {
    color: "bg-gray-400",
    label: status.status,
  };

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <div
          className={cn(
            "h-2.5 w-2.5 rounded-full",
            config.color,
            status.isRunning && "animate-pulse",
            className
          )}
        />
      </TooltipTrigger>
      <TooltipContent>
        <div className="text-xs">
          <div className="font-medium">{config.label}</div>
          {status.pid && <div className="text-muted-foreground">PID: {status.pid}</div>}
          {status.restarts !== undefined && status.restarts > 0 && (
            <div className="text-muted-foreground">Restarts: {status.restarts}</div>
          )}
          {status.exitCode !== undefined && (
            <div className="text-muted-foreground">Exit code: {status.exitCode}</div>
          )}
        </div>
      </TooltipContent>
    </Tooltip>
  );
}
