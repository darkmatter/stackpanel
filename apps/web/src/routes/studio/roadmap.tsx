/**
 * Roadmap Page
 *
 * Displays the StackPanel development roadmap showing current alpha features
 * and planned future capabilities based on the repo status.
 */

import { createFileRoute } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@ui/card";
import {
  CheckCircle2,
  Circle,
  Clock,
  Layers,
  Map,
  Puzzle,
  Rocket,
  Settings2,
  Sparkles,
  Target,
} from "lucide-react";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/studio/roadmap")({
  component: RoadmapPage,
});

interface RoadmapPhase {
  id: string;
  title: string;
  status: "current" | "upcoming" | "future";
  badge?: string;
  description: string;
  features: {
    name: string;
    description: string;
    status: "complete" | "in-progress" | "planned";
  }[];
  icon: React.ElementType;
}

const roadmapPhases: RoadmapPhase[] = [
  {
    id: "beta",
    title: "Beta",
    status: "current",
    badge: "Current",
    description:
      "Core StackPanel foundations: CLI + Studio, Support for main conventions, demonstrate moving config -> build.",
    icon: Rocket,
    features: [
      {
        name: "StackPanel CLI + TUI",
        description:
          "CLI commands, status dashboard, and interactive flows for managing services and environments.",
        status: "complete",
      },
      {
        name: "Deterministic Ports + Service Presets",
        description:
          "Built-in port allocation and default services like Postgres, Redis, Minio, and Caddy.",
        status: "complete",
      },
      {
        name: "Devenv Integration",
        description:
          "Devenv wrapper module, devshell setup, and process-compose orchestration.",
        status: "complete",
      },
      {
        name: "IDE Workspace Generation",
        description:
          "VS Code workspace config, terminal integration, and YAML schema generation.",
        status: "complete",
      },
      {
        name: "CI Workflow Generation",
        description: "GitHub Actions workflows generated from Nix modules.",
        status: "complete",
      },
      {
        name: "Generated Files Pipeline",
        description:
          "Ensure all generated files flow through stackpanel-managed config output.",
        status: "in-progress",
      },
      {
        name: "Secrets Management",
        description:
          "SOPS-backed secrets schema and codegen with improved sync automation.",
        status: "in-progress",
      },
    ],
  },
  {
    id: "v1",
    title: "Version 1",
    status: "upcoming",
    description:
      "All source code is related to product, wrapped binaries are the default. Wide support for languages/frameworks. Robust module and plugin ecosystem.",
    icon: Target,
    features: [
      {
        name: "Service Health Checks",
        description:
          "Traffic-light status checks across services with healthcheck hooks.",
        status: "planned",
      },
      {
        name: "Modular Services Registry",
        description:
          "Service modules register themselves instead of hard-coded service names.",
        status: "planned",
      },
      {
        name: "Agent Authentication",
        description:
          "Secure access to the local agent and improved WebSocket behavior.",
        status: "planned",
      },
      {
        name: "Secrets Sync Automation",
        description:
          "GitHub user sync, auto re-keying, and improved secrets workflows.",
        status: "planned",
      },
      {
        name: "AWS Module Hardening",
        description:
          "Expand AWS support beyond cert-based auth (IAM, S3, RDS, and more).",
        status: "planned",
      },
      {
        name: "Language Detection",
        description:
          "Auto-enable modules based on project layout and dependencies.",
        status: "planned",
      },
    ],
  },
  {
    id: "v2",
    title: "Version 2.0",
    status: "future",
    description:
      "Expand concept beyond local repo - include infra. All infra configuration lives with source. No two people in the planet configure the same thing twice (public remote cache).",
    icon: Puzzle,
    features: [
      {
        name: "Container Module",
        description:
          "Nix-based container builds with Dockerfile and compose generation.",
        status: "planned",
      },
      {
        name: "CI/CD Expansion",
        description:
          "Deploy/release workflows, caching options, and multi-provider CI support.",
        status: "planned",
      },
      {
        name: "Network Automation",
        description:
          "Tailscale auth, DNS automation, and mTLS across services.",
        status: "planned",
      },
      {
        name: "Plugin System",
        description: "Custom service definitions and modular extension points.",
        status: "planned",
      },
      {
        name: "Integration Tests",
        description:
          "End-to-end tests validating generated artifacts and module behavior.",
        status: "planned",
      },
    ],
  },
];

function StatusIcon({
  status,
}: {
  status: "complete" | "in-progress" | "planned";
}) {
  switch (status) {
    case "complete":
      return <CheckCircle2 className="h-4 w-4 text-emerald-500" />;
    case "in-progress":
      return <Clock className="h-4 w-4 text-amber-500 animate-pulse" />;
    case "planned":
      return <Circle className="h-4 w-4 text-muted-foreground" />;
  }
}

function PhaseCard({ phase }: { phase: RoadmapPhase }) {
  const Icon = phase.icon;
  const isCurrent = phase.status === "current";
  const isUpcoming = phase.status === "upcoming";

  return (
    <Card
      className={cn(
        "relative overflow-hidden transition-all",
        isCurrent && "border-accent ring-1 ring-accent/20",
      )}
    >
      {isCurrent && (
        <div className="absolute inset-x-0 top-0 h-1 bg-linear-to-r from-accent via-accent/80 to-accent" />
      )}
      <CardHeader>
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div
              className={cn(
                "flex h-10 w-10 items-center justify-center rounded-lg",
                isCurrent
                  ? "bg-accent/20 text-accent"
                  : isUpcoming
                    ? "bg-secondary text-muted-foreground"
                    : "bg-secondary/50 text-muted-foreground/60",
              )}
            >
              <Icon className="h-5 w-5" />
            </div>
            <div>
              <CardTitle className="flex items-center gap-2">
                {phase.title}
                {phase.badge && (
                  <Badge
                    variant={isCurrent ? "default" : "secondary"}
                    className={cn(
                      "text-xs",
                      isCurrent && "bg-accent text-accent-foreground",
                    )}
                  >
                    {phase.badge}
                  </Badge>
                )}
              </CardTitle>
              <CardDescription className="mt-1">
                {phase.description}
              </CardDescription>
            </div>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {phase.features.map((feature) => (
            <div
              key={feature.name}
              className={cn(
                "flex items-start gap-3 rounded-lg border p-3",
                feature.status === "complete" &&
                  "bg-emerald-500/5 border-emerald-500/20",
                feature.status === "in-progress" &&
                  "bg-amber-500/5 border-amber-500/20",
                feature.status === "planned" &&
                  "bg-secondary/30 border-transparent",
              )}
            >
              <StatusIcon status={feature.status} />
              <div className="flex-1 min-w-0">
                <p
                  className={cn(
                    "font-medium text-sm",
                    feature.status === "planned" && "text-muted-foreground",
                  )}
                >
                  {feature.name}
                </p>
                <p className="text-muted-foreground text-xs mt-0.5">
                  {feature.description}
                </p>
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

function RoadmapPage() {
  return (
    <div className="container mx-auto space-y-8 py-8">
      {/* Header */}
      <div className="space-y-4">
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-accent/10">
            <Map className="h-6 w-6 text-accent" />
          </div>
          <div>
            <h1 className="flex items-center gap-3 text-3xl font-bold">
              Roadmap
              <Badge className="bg-amber-500/20 text-amber-600 dark:text-amber-400 border-amber-500/30">
                <Sparkles className="h-3 w-3 mr-1" />
                Alpha
              </Badge>
            </h1>
            <p className="text-muted-foreground">
              See what's available now and what's coming next for StackPanel
            </p>
          </div>
        </div>
      </div>

      {/* Current Status Banner */}
      <Card className="bg-linear-to-br from-accent/5 via-accent/10 to-accent/5 border-accent/20">
        <CardContent className="p-6">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-accent/20">
              <Settings2 className="h-6 w-6 text-accent" />
            </div>
            <div className="space-y-2">
              <h2 className="font-semibold text-lg">Currently in Alpha</h2>
              <p className="text-muted-foreground text-sm leading-relaxed">
                StackPanel is currently in alpha, focused on a stable CLI, core
                Nix modules, and the local developer experience. As we move
                toward beta, we'll harden service management, secrets workflows,
                and agent security. The v1 roadmap expands into container and
                CI/CD automation with extensibility.
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Timeline Legend */}
      <div className="flex flex-wrap items-center gap-6 text-sm">
        <div className="flex items-center gap-2">
          <CheckCircle2 className="h-4 w-4 text-emerald-500" />
          <span className="text-muted-foreground">Complete</span>
        </div>
        <div className="flex items-center gap-2">
          <Clock className="h-4 w-4 text-amber-500" />
          <span className="text-muted-foreground">In Progress</span>
        </div>
        <div className="flex items-center gap-2">
          <Circle className="h-4 w-4 text-muted-foreground" />
          <span className="text-muted-foreground">Planned</span>
        </div>
      </div>

      {/* Roadmap Phases */}
      <div className="grid gap-6">
        {roadmapPhases.map((phase, index) => (
          <div key={phase.id} className="relative">
            {/* Connector line between phases */}
            {index < roadmapPhases.length - 1 && (
              <div className="absolute left-7 top-full h-6 w-px bg-border" />
            )}
            <PhaseCard phase={phase} />
          </div>
        ))}
      </div>

      {/* Footer Note */}
      <Card className="bg-secondary/30">
        <CardContent className="p-6">
          <div className="flex items-start gap-3">
            <Layers className="h-5 w-5 text-muted-foreground shrink-0 mt-0.5" />
            <div className="space-y-1">
              <p className="text-sm font-medium">About this Roadmap</p>
              <p className="text-muted-foreground text-xs leading-relaxed">
                This roadmap represents our current plans and priorities, but
                may change based on user feedback and evolving requirements.
                Features marked as "planned" are subject to change. We'd love to
                hear your thoughts on what would be most valuable!
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
