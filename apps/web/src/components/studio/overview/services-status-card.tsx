"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { CheckCircle2, Circle, Loader2, RefreshCw, Server, XCircle } from "lucide-react";
import { z } from "zod";
import { useAgentContext } from "@/lib/agent-provider";
import { useNixConfigQuery, useProcesses } from "@/lib/use-agent";
import { cn } from "@/lib/utils";

type ServiceStatus = "running" | "stopped" | "unknown";

interface Service {
  id: string;
  label: string;
  port?: number;
  status: ServiceStatus;
}

interface ProcessObservation {
  name: string;
  namespace: string;
  isRunning: boolean;
}

const serviceDefinition = z.object({
  enable: z.boolean(),
  displayName: z.string().nullish(),
  port: z.number().nullish(),
  "process-compose": z
    .object({ enable: z.boolean().optional(), namespace: z.string().optional() })
    .optional(),
});

const serviceConfig = z.object({
  services: z.record(z.string(), serviceDefinition),
});

function configuredServices(
  config: Record<string, unknown>,
  observations: readonly ProcessObservation[],
): Service[] | null {
  const root = serviceConfig.safeParse(config);
  if (!root.success) return null;

  // Process-compose uses the Nix service key as its process name. Do not
  // match display names or substrings (e.g. a service's migration worker).
  const byName = new Map(observations.map((process) => [process.name, process]));
  const services: Service[] = [];
  for (const [id, definition] of Object.entries(root.data.services)) {
    if (!definition.enable) continue;
    const pc = definition["process-compose"];
    const namespace = pc?.namespace ?? "services";
    const observation = byName.get(id);
    let status: ServiceStatus = "unknown";
    if (
      observation &&
      pc?.enable !== false &&
      (!observation.namespace || observation.namespace === namespace)
    ) {
      status = observation.isRunning ? "running" : "stopped";
    }
    services.push({
      id,
      label: definition.displayName ?? id,
      port: definition.port ?? undefined,
      status,
    });
  }
  return services;
}

const badges = {
  running: { Icon: CheckCircle2, label: "Running", style: "bg-emerald-500/10 text-emerald-500" },
  stopped: { Icon: XCircle, label: "Stopped", style: "bg-muted text-muted-foreground" },
  unknown: { Icon: Circle, label: "Unknown", style: "bg-muted text-muted-foreground" },
};

function ServiceList({ services }: { services: Service[] }) {
  return (
    <ul className="space-y-3">
      {services.map((service) => {
        const { Icon, label, style } = badges[service.status];
        return (
          <li
            key={service.id}
            className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 px-4 py-3"
          >
            <div>
              <p className="text-sm font-medium">{service.label}</p>
              {service.port != null && (
                <p className="text-xs text-muted-foreground">Port {service.port}</p>
              )}
            </div>
            <span
              className={cn(
                "flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium",
                style,
              )}
            >
              <Icon className="size-3.5" />
              {label}
            </span>
          </li>
        );
      })}
    </ul>
  );
}

export function ServicesStatusCard() {
  const { isConnected, selectedProjectId } = useAgentContext();
  const config = useNixConfigQuery();
  const processes = useProcesses();
  // GetProcesses observes the agent's local process-compose instance, not
  // an explicitly selected project's instance. Never join the two by ID.
  const processError = selectedProjectId
    ? "the process monitor is agent-wide, not scoped to the selected project"
    : processes.error?.message || processes.data?.error;
  const live = !processError && processes.data?.available;
  const services =
    isConnected && !config.error && config.data?.config
      ? configuredServices(config.data.config, live ? (processes.data?.processes ?? []) : [])
      : null;
  const refreshing = config.isFetching || (!selectedProjectId && processes.isFetching);
  const running = services?.filter((service) => service.status === "running").length ?? 0;
  const allObserved =
    !!services?.length && services.every((service) => service.status !== "unknown");

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-3">
        <CardTitle className="flex items-center gap-2 text-base font-medium">
          <Server className="size-4 text-accent" /> Services
          {allObserved && (
            <span className="text-xs font-normal text-muted-foreground">
              ({running}/{services?.length} running)
            </span>
          )}
        </CardTitle>
        <Button
          aria-label="Refresh service status"
          variant="ghost"
          size="sm"
          className="size-8 p-0"
          disabled={!isConnected || refreshing}
          onClick={() => Promise.all([config.refetch(), !selectedProjectId && processes.refetch()])}
        >
          <RefreshCw className={cn("size-4", refreshing && "animate-spin")} />
        </Button>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        {!isConnected ? (
          <p className="text-muted-foreground">Connect to the agent to view services.</p>
        ) : config.isLoading ? (
          <p role="status" className="flex items-center gap-2 text-muted-foreground">
            <Loader2 className="size-4 animate-spin" /> Loading services…
          </p>
        ) : !services ? (
          <p role="alert" className="text-destructive">
            Service configuration is unavailable{config.error ? `: ${config.error.message}` : "."}
          </p>
        ) : services.length === 0 ? (
          <p className="text-muted-foreground">
            No enabled services. Enable services in your Nix configuration.
          </p>
        ) : (
          <>
            {!selectedProjectId && processes.isLoading ? (
              <p role="status" className="text-muted-foreground">
                Loading live service status…
              </p>
            ) : (
              !live && (
                <p role="status" className="text-muted-foreground">
                  Live service status is unavailable{processError ? `: ${processError}` : "."}
                </p>
              )
            )}
            <ServiceList services={services} />
            <div className="rounded-lg border border-border bg-secondary/30 p-3">
              <p className="font-medium">
                {!allObserved
                  ? "Some service statuses could not be confirmed"
                  : running === services.length
                    ? "All services running"
                    : `${services.length - running} stopped`}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                Run <code className="rounded bg-muted px-1">dev</code> to start process-compose.
              </p>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
