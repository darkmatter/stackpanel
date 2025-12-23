"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

export function TerminalSection() {
  const [activeTab, setActiveTab] = useState("create");

  const tabs = [
    { id: "create", label: "Create App" },
    { id: "install", label: "Install Service" },
    { id: "deploy", label: "Deploy" },
  ];

  const terminalContent: Record<string, { command: string; output: string[] }> = {
    create: {
      command: "create-app payments-api --template=api",
      output: [
        "→ Creating new application...",
        "✓ Initialized turborepo workspace",
        "✓ Applied stack configuration (neon, redis, observability)",
        "✓ Created GitHub repo: acme-corp/payments-api",
        "✓ Configured CI/CD pipeline",
        "✓ Added to StackPanel dashboard",
        "",
        "cd payments-api && nix develop",
      ],
    },
    install: {
      command: "x install neon",
      output: [
        "→ Installing Neon integration...",
        "✓ Added @neondatabase/serverless to dependencies",
        "✓ Created lib/db.ts with connection pool",
        "✓ Added DATABASE_URL to secrets",
        "✓ Updated nix flake with pg_dump tools",
        "✓ Generated migration scaffolding",
        "",
        "Run 'x db:migrate' to create your first migration",
      ],
    },
    deploy: {
      command: "x deploy production",
      output: [
        "→ Deploying to production...",
        "✓ Building container image (2.3s)",
        "✓ Pushing to internal registry",
        "✓ Updating GitOps repo",
        "✓ ArgoCD syncing deployment",
        "✓ Health checks passing",
        "",
        "🚀 Live at https://payments-api.acme-corp.com",
      ],
    },
  };

  return (
    <section className="border-border border-b bg-secondary/20">
      <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="text-center">
          <p className="font-medium text-accent text-sm">CLI Tools</p>
          <h2 className="mt-4 text-balance font-bold text-3xl text-foreground sm:text-4xl">
            Powerful commands at your fingertips
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
            Tools automatically available in your PATH. No installation needed—just
            enter your dev shell and start building.
          </p>
        </div>

        <div className="mx-auto mt-12 max-w-3xl">
          <div className="overflow-hidden rounded-xl border border-border bg-card shadow-xl">
            <div className="flex items-center justify-between border-border border-b bg-secondary/50 px-4">
              <div className="flex">
                {tabs.map((tab) => (
                  <button
                    className={cn(
                      "border-b-2 px-4 py-3 font-medium text-sm transition-colors",
                      activeTab === tab.id
                        ? "border-accent text-foreground"
                        : "border-transparent text-muted-foreground hover:text-foreground"
                    )}
                    key={tab.id}
                    onClick={() => setActiveTab(tab.id)}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>
              <div className="flex gap-1.5">
                <div className="h-3 w-3 rounded-full bg-red-500/80" />
                <div className="h-3 w-3 rounded-full bg-yellow-500/80" />
                <div className="h-3 w-3 rounded-full bg-green-500/80" />
              </div>
            </div>

            <div className="p-6 font-mono text-sm">
              <div className="flex items-center gap-2">
                <span className="text-accent">$</span>
                <span className="text-foreground">
                  {terminalContent[activeTab].command}
                </span>
              </div>
              <div className="mt-4 space-y-1">
                {terminalContent[activeTab].output.map((line, i) => (
                  <div
                    className={cn(
                      line.startsWith("✓")
                        ? "text-accent"
                        : line.startsWith("→")
                          ? "text-muted-foreground"
                          : line.startsWith("🚀")
                            ? "font-semibold text-accent"
                            : line === ""
                              ? "h-4"
                              : "text-muted-foreground"
                    )}
                    key={i}
                  >
                    {line}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
