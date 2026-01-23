"use client";

import { Button } from "@ui/button";
import {
  Check,
  CheckCircle2,
  Database,
  Folder,
  FolderOpen,
  GitBranch,
  Home,
  Settings,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

interface KeyLocation {
  id: string;
  path: string;
  description: string;
  icon: React.ElementType;
  iconColor: string;
  badges: { label: string; className: string }[];
}

export function ProjectInfoStep() {
  const {
    expandedStep,
    setExpandedStep,
    isConnected,
    projectName,
    githubRepo,
    homeDirPath,
    dataPath,
    genPath,
    statePath,
    projectConfirmed,
    confirmProject,
  } = useSetupContext();

  const step: SetupStep = {
    id: "project-info",
    title: "Confirm Directories",
    description: "How Stackpanel organizes your project",
    status: projectConfirmed
      ? "complete"
      : isConnected
        ? "incomplete"
        : "blocked",
    required: true,
    dependsOn: ["connect-agent"],
    icon: <FolderOpen className="h-5 w-5" />,
  };

  const keyLocations: KeyLocation[] = [
    {
      id: "data",
      path: dataPath,
      description:
        "Your Stackpanel configuration. The UI edits these Nix files to customize your setup, secrets schemas, and project settings.",
      icon: Settings,
      iconColor: "text-emerald-500",
      badges: [
        {
          label: "user-editable",
          className: "bg-emerald-500/10 text-emerald-400",
        },
        { label: "git tracked", className: "bg-blue-500/10 text-blue-400" },
      ],
    },
    {
      id: "gen",
      path: genPath,
      description:
        "Auto-generated files from Nix. These are rebuilt when you enter the devshell. Generated files can land anywhere, but will land here by default.",
      icon: Folder,
      iconColor: "text-amber-500",
      badges: [
        { label: "generated", className: "bg-amber-500/10 text-amber-400" },
        { label: "git tracked", className: "bg-blue-500/10 text-blue-400" },
      ],
    },
    {
      id: "state",
      path: statePath,
      description:
        "Runtime state like current configuration snapshot and your machine-specific configuration. Rebuilt each shell entry. Not tracked in git.",
      icon: Database,
      iconColor: "text-purple-500",
      badges: [
        { label: "runtime", className: "bg-purple-500/10 text-purple-400" },
        { label: "gitignored", className: "bg-muted text-muted-foreground" },
      ],
    },
    {
      id: "home",
      path: homeDirPath,
      description:
        "Stackpanel home: The above directories, and any other files related to Stackpanel will be stored here.",
      icon: Home,
      iconColor: "text-rose-500",
      badges: [
        { label: "user-specific", className: "bg-rose-500/10 text-rose-400" },
        { label: "outside repo", className: "bg-muted text-muted-foreground" },
      ],
    },
  ];

  return (
    <StepCard
      step={step}
      isExpanded={expandedStep === "project-info"}
      onToggle={() =>
        setExpandedStep(expandedStep === "project-info" ? null : "project-info")
      }
    >
      <div className="space-y-6">
        <p className="text-sm text-muted-foreground">
          Stackpanel organizes your project using four key locations.
          Understanding these will help you know where to find and edit
          configuration.
        </p>

        {/* Project Identity */}
        <div className="space-y-3">
          <h4 className="font-medium flex items-center gap-2">
            <GitBranch className="h-4 w-4" />
            Project Identity
          </h4>
          <div className="grid gap-2 pl-6">
            <div className="flex items-center justify-between p-2 rounded-lg bg-muted/50">
              <span className="text-sm">Project Name</span>
              <code className="text-sm font-mono bg-background px-2 py-0.5 rounded">
                {projectName}
              </code>
            </div>
            <div className="flex items-center justify-between p-2 rounded-lg bg-muted/50">
              <span className="text-sm">GitHub Repository</span>
              <code className="text-sm font-mono bg-background px-2 py-0.5 rounded">
                {githubRepo || (
                  <span className="text-muted-foreground">not configured</span>
                )}
              </code>
            </div>
            <div className="flex items-center justify-between p-2 rounded-lg bg-muted/50">
              <span className="text-sm">Home Directory</span>
              <code className="text-sm font-mono bg-background px-2 py-0.5 rounded">
                {homeDirPath}
              </code>
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              Configure these in <code>.stackpanel/config.nix</code>
            </p>
          </div>
        </div>

        {/* Key Locations */}
        <div className="space-y-3">
          <h4 className="font-medium flex items-center gap-2">
            <Folder className="h-4 w-4" />
            Key Locations
          </h4>
          <div className="grid gap-3">
            {keyLocations.map((location) => {
              const Icon = location.icon;
              return (
                <div
                  key={location.id}
                  className="rounded-lg border p-4 space-y-2"
                >
                  <div className="flex items-center gap-2 flex-wrap">
                    <Icon className={cn("h-4 w-4", location.iconColor)} />
                    <code className="font-mono text-sm font-medium">
                      {location.path}
                    </code>
                    {location.badges.map((badge) => (
                      <span
                        key={badge.label}
                        className={cn(
                          "text-xs px-1.5 py-0.5 rounded",
                          badge.className,
                        )}
                      >
                        {badge.label}
                      </span>
                    ))}
                  </div>
                  <p className="text-sm text-muted-foreground">
                    {location.description}
                  </p>
                </div>
              );
            })}
          </div>
        </div>

        {projectConfirmed ? (
          <div className="rounded-lg bg-emerald-700/10 border border-emerald-500/20 p-3">
            <p className="text-sm text-emerald-700 dark:text-emerald-200 flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4" />
              Directory structure understood
            </p>
          </div>
        ) : (
          <Button onClick={confirmProject}>
            <Check className="h-4 w-4 mr-2" />
            Got It, Continue
          </Button>
        )}
      </div>
    </StepCard>
  );
}
