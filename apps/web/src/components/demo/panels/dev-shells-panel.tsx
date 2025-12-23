"use client";

import { Code, FileCode, GitBranch, Package, Play, Plus, Terminal } from "lucide-react";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const devShells = [
  {
    name: "default",
    description: "Standard development environment",
    languages: ["Node.js 20", "Python 3.11", "Go 1.21"],
    tools: ["git", "docker", "kubectl", "terraform"],
    hooks: ["pre-commit", "commit-msg"],
    active: true,
  },
  {
    name: "frontend",
    description: "Frontend development with React tooling",
    languages: ["Node.js 20", "Bun 1.0"],
    tools: ["pnpm", "turbo", "playwright"],
    hooks: ["pre-commit"],
    active: true,
  },
  {
    name: "data",
    description: "Data science and ML environment",
    languages: ["Python 3.11", "Julia 1.9"],
    tools: ["jupyter", "dvc", "mlflow"],
    hooks: [],
    active: false,
  },
  {
    name: "infra",
    description: "Infrastructure and DevOps tooling",
    languages: ["Go 1.21", "Python 3.11"],
    tools: ["terraform", "pulumi", "ansible", "k9s"],
    hooks: ["pre-commit"],
    active: true,
  },
];

const availableTools = [
  { id: "nodejs", name: "Node.js", version: "20.10.0", category: "language" },
  { id: "python", name: "Python", version: "3.11.7", category: "language" },
  { id: "go", name: "Go", version: "1.21.5", category: "language" },
  { id: "rust", name: "Rust", version: "1.74.0", category: "language" },
  { id: "bun", name: "Bun", version: "1.0.18", category: "runtime" },
  { id: "deno", name: "Deno", version: "1.38.4", category: "runtime" },
  { id: "docker", name: "Docker", version: "24.0.7", category: "tool" },
  { id: "kubectl", name: "kubectl", version: "1.28.4", category: "tool" },
  { id: "terraform", name: "Terraform", version: "1.6.5", category: "tool" },
  { id: "pnpm", name: "pnpm", version: "8.12.0", category: "tool" },
];

export function DevShellsPanel() {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [activeTab, setActiveTab] = useState("shells");

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="font-semibold text-foreground text-xl">Dev Shells</h2>
          <p className="text-muted-foreground text-sm">
            Nix-based development environments powered by devenv
          </p>
        </div>
        <Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
          <DialogTrigger asChild>
            <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
              <Plus className="h-4 w-4" />
              Create Shell
            </Button>
          </DialogTrigger>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>Create Dev Shell</DialogTitle>
              <DialogDescription>
                Configure a new Nix development environment for your team.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="shell-name">Shell Name</Label>
                <Input id="shell-name" placeholder="my-shell" />
              </div>
              <div className="grid gap-2">
                <Label>Languages & Runtimes</Label>
                <div className="grid grid-cols-3 gap-2">
                  {availableTools
                    .filter(
                      (t) => t.category === "language" || t.category === "runtime"
                    )
                    .map((tool) => (
                      <label
                        className="flex cursor-pointer items-center gap-2 rounded-lg border border-border p-3 hover:bg-secondary/50"
                        key={tool.id}
                      >
                        <Checkbox id={tool.id} />
                        <div className="text-sm">
                          <p className="font-medium text-foreground">{tool.name}</p>
                          <p className="text-muted-foreground text-xs">
                            {tool.version}
                          </p>
                        </div>
                      </label>
                    ))}
                </div>
              </div>
              <div className="grid gap-2">
                <Label>Git Hooks</Label>
                <div className="flex gap-4">
                  <label className="flex items-center gap-2">
                    <Checkbox id="pre-commit" />
                    <span className="text-sm">pre-commit</span>
                  </label>
                  <label className="flex items-center gap-2">
                    <Checkbox id="commit-msg" />
                    <span className="text-sm">commit-msg</span>
                  </label>
                  <label className="flex items-center gap-2">
                    <Checkbox id="pre-push" />
                    <span className="text-sm">pre-push</span>
                  </label>
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button onClick={() => setDialogOpen(false)} variant="outline">
                Cancel
              </Button>
              <Button className="bg-accent text-accent-foreground hover:bg-accent/90">
                Create Shell
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      <Tabs onValueChange={setActiveTab} value={activeTab}>
        <TabsList>
          <TabsTrigger value="shells">Shells</TabsTrigger>
          <TabsTrigger value="tools">Available Tools</TabsTrigger>
          <TabsTrigger value="scripts">Scripts</TabsTrigger>
        </TabsList>

        <TabsContent className="mt-6 space-y-4" value="shells">
          {devShells.map((shell) => (
            <Card key={shell.name}>
              <CardContent className="p-6">
                <div className="flex items-start justify-between">
                  <div className="flex items-start gap-4">
                    <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-accent/10">
                      <Terminal className="h-6 w-6 text-accent" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className="font-medium text-foreground">{shell.name}</h3>
                        {shell.active && (
                          <Badge
                            className="border-accent text-accent"
                            variant="outline"
                          >
                            Active
                          </Badge>
                        )}
                      </div>
                      <p className="mt-1 text-muted-foreground text-sm">
                        {shell.description}
                      </p>

                      <div className="mt-4 space-y-3">
                        <div className="flex items-center gap-2">
                          <Code className="h-4 w-4 text-muted-foreground" />
                          <div className="flex flex-wrap gap-1">
                            {shell.languages.map((lang) => (
                              <Badge className="text-xs" key={lang} variant="secondary">
                                {lang}
                              </Badge>
                            ))}
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Package className="h-4 w-4 text-muted-foreground" />
                          <div className="flex flex-wrap gap-1">
                            {shell.tools.map((tool) => (
                              <Badge className="text-xs" key={tool} variant="outline">
                                {tool}
                              </Badge>
                            ))}
                          </div>
                        </div>
                        {shell.hooks.length > 0 && (
                          <div className="flex items-center gap-2">
                            <GitBranch className="h-4 w-4 text-muted-foreground" />
                            <div className="flex flex-wrap gap-1">
                              {shell.hooks.map((hook) => (
                                <Badge
                                  className="border-accent/50 text-accent text-xs"
                                  key={hook}
                                  variant="outline"
                                >
                                  {hook}
                                </Badge>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-4">
                    <div className="flex items-center gap-2">
                      <Label
                        className="text-muted-foreground text-sm"
                        htmlFor={`active-${shell.name}`}
                      >
                        Active
                      </Label>
                      <Switch checked={shell.active} id={`active-${shell.name}`} />
                    </div>
                    <Button size="sm" variant="outline">
                      Edit
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </TabsContent>

        <TabsContent className="mt-6" value="tools">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {availableTools.map((tool) => (
              <Card
                className="cursor-pointer transition-colors hover:border-accent/50"
                key={tool.id}
              >
                <CardContent className="flex items-center gap-4 p-4">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
                    <Package className="h-5 w-5 text-muted-foreground" />
                  </div>
                  <div className="flex-1">
                    <p className="font-medium text-foreground">{tool.name}</p>
                    <p className="text-muted-foreground text-sm">{tool.version}</p>
                  </div>
                  <Badge className="text-xs" variant="outline">
                    {tool.category}
                  </Badge>
                </CardContent>
              </Card>
            ))}
          </div>
        </TabsContent>

        <TabsContent className="mt-6 space-y-4" value="scripts">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <FileCode className="h-5 w-5 text-accent" />
                Available Scripts
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {[
                {
                  name: "create-app",
                  description: "Create a new app with turborepo template",
                },
                {
                  name: "x",
                  description: "Stack management CLI (install, configure, deploy)",
                },
                { name: "db", description: "Database management utilities" },
                { name: "secrets", description: "Manage encrypted secrets" },
                { name: "logs", description: "Tail service logs" },
              ].map((script) => (
                <div
                  className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
                  key={script.name}
                >
                  <div className="flex items-center gap-3">
                    <code className="font-medium text-accent text-sm">
                      {script.name}
                    </code>
                    <span className="text-muted-foreground text-sm">
                      {script.description}
                    </span>
                  </div>
                  <Button className="gap-2" size="sm" variant="ghost">
                    <Play className="h-4 w-4" />
                    Run
                  </Button>
                </div>
              ))}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
