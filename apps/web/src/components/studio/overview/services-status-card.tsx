"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Button } from "@ui/button";
import {
  CheckCircle2,
  Circle,
  Database,
  HardDrive,
  Loader2,
  RefreshCw,
  Server,
  XCircle,
} from "lucide-react";
import { useMemo } from "react";
import { useProcesses, useNixConfigQuery } from "@/lib/use-agent";
import { useAgentContext } from "@/lib/agent-provider";
import { cn } from "@/lib/utils";

interface ServiceInfo {
  name: string;
  displayName: string;
  icon: React.ComponentType<{ className?: string }>;
  enabled: boolean;
  running: boolean;
  port?: number;
  status: "running" | "stopped" | "unknown";
}

/**
 * Card showing the status of infrastructure services (Postgres, Redis, Minio, Caddy).
 * Uses nix config to determine which services are enabled, and process-compose to check if running.
 */
export function ServicesStatusCard() {
  const { isConnected } = useAgentContext();
  const { data: nixConfig, isLoading: configLoading } = useNixConfigQuery();
  const { data: processes, isLoading: processesLoading, refetch } = useProcesses();

  const services = useMemo((): ServiceInfo[] => {
    const config = nixConfig?.config as Record<string, unknown> | null;
    const processList = processes?.processes ?? [];

    // Helper to check if a process is running (by exact name or substring match)
    const isRunning = (names: string[]): boolean => {
      return processList.some(p => 
        names.some(name => p.name.toLowerCase().includes(name.toLowerCase())) && p.isRunning
      );
    };

    const result: ServiceInfo[] = [];

    // Read from stackpanel.services (new canonical format)
    const stackpanelServices = (config?.services ?? {}) as Record<string, Record<string, unknown>>;
    for (const [name, svc] of Object.entries(stackpanelServices)) {
      if (svc && svc.enable === true) {
        const displayName = (svc.displayName as string) ?? name;
        const icon = name.includes("postgres") ? Database
          : name.includes("minio") ? HardDrive
          : Server;
        result.push({
          name,
          displayName,
          icon,
          enabled: true,
          running: isRunning([name]),
          port: svc.port as number | undefined,
          status: isRunning([name]) ? "running" : "stopped",
        });
      }
    }

    // Fallback: also check globalServices for backward compatibility
    if (result.length === 0) {
      const globalServices = (config?.globalServices ?? {}) as Record<string, unknown>;
      const getServiceConfig = (svcName: string) =>
        (globalServices[svcName] ?? {}) as Record<string, unknown>;

      const postgresConfig = getServiceConfig("postgres");
      const redisConfig = getServiceConfig("redis");
      const minioConfig = getServiceConfig("minio");
      const caddyConfig = getServiceConfig("caddy");

      if (postgresConfig.enable === true) {
        result.push({
          name: "postgres", displayName: "PostgreSQL", icon: Database,
          enabled: true, running: isRunning(["postgres", "postgresql"]),
          port: postgresConfig.port as number | undefined,
          status: isRunning(["postgres", "postgresql"]) ? "running" : "stopped",
        });
      }
      if (redisConfig.enable === true) {
        result.push({
          name: "redis", displayName: "Redis", icon: Server,
          enabled: true, running: isRunning(["redis"]),
          port: redisConfig.port as number | undefined,
          status: isRunning(["redis"]) ? "running" : "stopped",
        });
      }
      if (minioConfig.enable === true) {
        result.push({
          name: "minio", displayName: "Minio", icon: HardDrive,
          enabled: true, running: isRunning(["minio"]),
          port: minioConfig.port as number | undefined,
          status: isRunning(["minio"]) ? "running" : "stopped",
        });
      }
      if (caddyConfig.enable === true) {
        result.push({
          name: "caddy", displayName: "Caddy", icon: Server,
          enabled: true, running: isRunning(["caddy"]),
          status: isRunning(["caddy"]) ? "running" : "stopped",
        });
      }
    }

    return result;
  }, [nixConfig, processes]);

  const enabledServices = services.filter(s => s.enabled);
  const runningCount = enabledServices.filter(s => s.running).length;
  const isLoading = configLoading || processesLoading;

  if (!isConnected) {
    return (
      <Card className="opacity-50">
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base font-medium">
            <Server className="h-4 w-4 text-muted-foreground" />
            Services
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">Connect to agent to view services</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-3">
        <CardTitle className="flex items-center gap-2 text-base font-medium">
          <Server className="h-4 w-4 text-accent" />
          Services
          {!isLoading && enabledServices.length > 0 && (
            <span className="text-xs font-normal text-muted-foreground">
              ({runningCount}/{enabledServices.length} running)
            </span>
          )}
        </CardTitle>
        <Button
          variant="ghost"
          size="sm"
          className="h-8 w-8 p-0"
          onClick={() => refetch()}
          disabled={isLoading}
        >
          <RefreshCw className={cn("h-4 w-4", isLoading && "animate-spin")} />
        </Button>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="flex items-center justify-center py-6">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : enabledServices.length === 0 ? (
          <div className="py-4 text-center">
            <p className="text-sm text-muted-foreground">No services configured</p>
            <p className="text-xs text-muted-foreground mt-1">
              Enable services in your Nix configuration
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {services.map((service) => {
              const Icon = service.icon;
              
              if (!service.enabled) {
                return null;
              }

              return (
                <div
                  key={service.name}
                  className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 px-4 py-3"
                >
                  <div className="flex items-center gap-3">
                    <div className={cn(
                      "flex h-9 w-9 items-center justify-center rounded-lg",
                      service.running ? "bg-emerald-500/10" : "bg-muted"
                    )}>
                      <Icon className={cn(
                        "h-4 w-4",
                        service.running ? "text-emerald-500" : "text-muted-foreground"
                      )} />
                    </div>
                    <div>
                      <p className="font-medium text-sm text-foreground">
                        {service.displayName}
                      </p>
                      {service.port && (
                        <p className="text-xs text-muted-foreground">
                          Port {service.port}
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <ServiceStatusBadge status={service.status} />
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Summary footer */}
        {!isLoading && enabledServices.length > 0 && (
          <div className="mt-4 rounded-lg border border-border bg-secondary/30 p-3">
            <div className="flex items-center gap-2">
              {runningCount === enabledServices.length ? (
                <>
                  <span className="h-2 w-2 rounded-full bg-emerald-500" />
                  <span className="font-medium text-foreground text-sm">
                    All services running
                  </span>
                </>
              ) : runningCount > 0 ? (
                <>
                  <span className="h-2 w-2 rounded-full bg-yellow-500" />
                  <span className="font-medium text-foreground text-sm">
                    {enabledServices.length - runningCount} service(s) stopped
                  </span>
                </>
              ) : (
                <>
                  <span className="h-2 w-2 rounded-full bg-red-500" />
                  <span className="font-medium text-foreground text-sm">
                    No services running
                  </span>
                </>
              )}
            </div>
            <p className="mt-1 text-muted-foreground text-xs">
              Run <code className="rounded bg-muted px-1">dev</code> to start all services with process-compose
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function ServiceStatusBadge({ status }: { status: "running" | "stopped" | "unknown" }) {
  switch (status) {
    case "running":
      return (
        <div className="flex items-center gap-1.5 rounded-full bg-emerald-500/10 px-2.5 py-1 text-emerald-500">
          <CheckCircle2 className="h-3.5 w-3.5" />
          <span className="text-xs font-medium">Running</span>
        </div>
      );
    case "stopped":
      return (
        <div className="flex items-center gap-1.5 rounded-full bg-muted px-2.5 py-1 text-muted-foreground">
          <XCircle className="h-3.5 w-3.5" />
          <span className="text-xs font-medium">Stopped</span>
        </div>
      );
    default:
      return (
        <div className="flex items-center gap-1.5 rounded-full bg-muted px-2.5 py-1 text-muted-foreground">
          <Circle className="h-3.5 w-3.5" />
          <span className="text-xs font-medium">Disabled</span>
        </div>
      );
  }
}
