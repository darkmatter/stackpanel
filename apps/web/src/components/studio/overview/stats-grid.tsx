"use client";

import { Link } from "@tanstack/react-router";
import { Card, CardContent } from "@ui/card";
import {
  ArrowUpRight,
  Box,
  KeyRound,
  Loader2,
  Package,
  PlayCircle,
  Server,
  Users,
  Variable,
} from "lucide-react";
import { useMemo } from "react";
import {
  useApps,
  useUsers,
  useSecrets,
  useVariables,
  useProcesses,
  useInstalledPackages,
} from "@/lib/use-agent";
import { useAgentContext } from "@/lib/agent-provider";

interface StatItem {
  label: string;
  value: string | number;
  subtitle?: string;
  icon: React.ComponentType<{ className?: string }>;
  path: string;
  loading?: boolean;
}

/**
 * Stats grid showing real data from the agent.
 * Displays: Apps, Variables, Secrets, Team Members, Running Processes, Packages
 */
export function StatsGrid() {
  const { isConnected } = useAgentContext();
  
  const { data: apps, isLoading: appsLoading } = useApps();
  const { data: users, isLoading: usersLoading } = useUsers();
  const { data: secrets, isLoading: secretsLoading } = useSecrets();
  const { data: variables, isLoading: variablesLoading } = useVariables();
  const { data: processes, isLoading: processesLoading } = useProcesses();
  const { data: packages, isLoading: packagesLoading } = useInstalledPackages();

  const stats = useMemo((): StatItem[] => {
    // Count apps
    const appCount = apps ? Object.keys(apps).length : 0;
    
    // Count team members
    const userCount = users?.users ? Object.keys(users.users).length : 0;
    
    // Count secrets across all environments
    const secretCount = secrets?.environments 
      ? Object.values(secrets.environments).reduce((total, env) => {
          // Each environment has sources (encrypted files)
          return total + (env.sources?.length ?? 0);
        }, 0)
      : 0;
    
    // Count variables
    const variableCount = variables ? Object.keys(variables).length : 0;
    
    // Count running processes
    const runningProcesses = processes?.processes?.filter(p => p.isRunning)?.length ?? 0;
    const totalProcesses = processes?.processes?.length ?? 0;
    
    // Count packages
    const packageCount = packages?.count ?? packages?.packages?.length ?? 0;

    return [
      {
        label: "Apps",
        value: appCount,
        subtitle: appCount === 1 ? "1 app configured" : `${appCount} apps configured`,
        icon: Box,
        path: "/studio/apps",
        loading: appsLoading,
      },
      {
        label: "Variables",
        value: variableCount,
        subtitle: "Environment variables",
        icon: Variable,
        path: "/studio/variables",
        loading: variablesLoading,
      },
      {
        label: "Secrets",
        value: secretCount,
        subtitle: "Across all environments",
        icon: KeyRound,
        path: "/studio/secrets",
        loading: secretsLoading,
      },
      {
        label: "Team",
        value: userCount,
        subtitle: userCount === 1 ? "1 team member" : `${userCount} team members`,
        icon: Users,
        path: "/studio/team",
        loading: usersLoading,
      },
      {
        label: "Processes",
        value: totalProcesses > 0 ? `${runningProcesses}/${totalProcesses}` : "0",
        subtitle: runningProcesses > 0 ? `${runningProcesses} running` : "None running",
        icon: PlayCircle,
        path: "/studio/services",
        loading: processesLoading,
      },
      {
        label: "Packages",
        value: packageCount,
        subtitle: "Installed via Nix",
        icon: Package,
        path: "/studio/packages",
        loading: packagesLoading,
      },
    ];
  }, [
    apps, appsLoading,
    users, usersLoading,
    secrets, secretsLoading,
    variables, variablesLoading,
    processes, processesLoading,
    packages, packagesLoading,
  ]);

  if (!isConnected) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        {[...Array(6)].map((_, i) => (
          <Card key={i} className="opacity-50">
            <CardContent className="p-6">
              <div className="flex items-center justify-between">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-muted">
                  <Server className="h-5 w-5 text-muted-foreground" />
                </div>
              </div>
              <div className="mt-4">
                <p className="font-bold text-3xl text-muted-foreground">-</p>
                <p className="text-muted-foreground text-sm">Not connected</p>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    );
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
      {stats.map((stat) => {
        const Icon = stat.icon;
        return (
          <Link key={stat.label} to={stat.path}>
            <Card className="cursor-pointer transition-colors hover:border-accent/50">
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                    <Icon className="h-5 w-5 text-accent" />
                  </div>
                  <ArrowUpRight className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="mt-4">
                  {stat.loading ? (
                    <div className="flex items-center gap-2">
                      <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                    </div>
                  ) : (
                    <p className="font-bold text-3xl text-foreground">
                      {stat.value}
                    </p>
                  )}
                  <p className="text-muted-foreground text-sm">{stat.label}</p>
                </div>
                <p className="mt-2 text-muted-foreground text-xs truncate">
                  {stat.subtitle}
                </p>
              </CardContent>
            </Card>
          </Link>
        );
      })}
    </div>
  );
}
