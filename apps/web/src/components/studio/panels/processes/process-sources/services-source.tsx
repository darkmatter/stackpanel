"use client";

import { Badge } from "@ui/badge";
import { Checkbox } from "@ui/checkbox";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@ui/tooltip";
import { Database, HardDrive, Server } from "lucide-react";
import type { SourceTabProps } from "../types";
import { ProcessStatusIndicator } from "../process-status-indicator";

const SERVICE_ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  postgres: Database,
  postgresql: Database,
  redis: Server,
  minio: HardDrive,
};

function getServiceIcon(name: string) {
  const lower = name.toLowerCase();
  for (const [key, Icon] of Object.entries(SERVICE_ICONS)) {
    if (lower.includes(key)) return Icon;
  }
  return Server;
}

export function ServicesSource({ sources, statuses, onToggle }: SourceTabProps) {
  if (sources.length === 0) {
    return (
      <div className="py-8 text-center">
        <Server className="mx-auto h-12 w-12 text-muted-foreground/50" />
        <p className="mt-2 text-muted-foreground">
          No services configured
        </p>
        <p className="mt-1 text-sm text-muted-foreground/70">
          Enable services in{" "}
          <code className="rounded bg-secondary px-1 py-0.5">
            stackpanel.globalServices
          </code>{" "}
          or{" "}
          <code className="rounded bg-secondary px-1 py-0.5">
            stackpanel.services
          </code>
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {sources.map((source) => {
        const status = statuses[source.name];
        const Icon = getServiceIcon(source.name);
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

            <div className="flex items-center gap-2">
              <Icon className="h-4 w-4 text-muted-foreground" />
            </div>

            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="font-medium truncate">
                  {source.displayName ?? source.name}
                </span>
                <Badge variant="outline" className="text-xs">
                  services
                </Badge>
                {!source.autoStart && (
                  <Badge variant="secondary" className="text-xs">
                    manual
                  </Badge>
                )}
              </div>
              <div className="flex items-center gap-3 text-xs text-muted-foreground">
                {source.port && (
                  <span>Port {source.port}</span>
                )}
                {source.description && (
                  <span className="truncate">{source.description}</span>
                )}
              </div>
            </div>

            {source.port && (
              <Tooltip>
                <TooltipTrigger asChild>
                  <div className="flex items-center gap-1 text-xs text-muted-foreground font-mono">
                    :{source.port}
                  </div>
                </TooltipTrigger>
                <TooltipContent>
                  <span>Listening on port {source.port}</span>
                </TooltipContent>
              </Tooltip>
            )}
          </div>
        );
      })}
    </div>
  );
}
