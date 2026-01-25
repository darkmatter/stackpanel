"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@ui/card";
import { Label } from "@ui/label";
import { RadioGroup, RadioGroupItem } from "@ui/radio-group";
import { Switch } from "@ui/switch";
import { AlertCircle, FileCode, FolderOpen, Settings } from "lucide-react";
import type { UseConfigurationResult } from "../use-configuration";

interface IdeSectionProps {
  config: UseConfigurationResult;
}

export function IdeSection({ config }: IdeSectionProps) {
  const isVscodeWorkspaceMode = config.vscodeOutputMode === "workspace";
  const isZedGeneratedMode = config.zedOutputMode === "generated";

  return (
    <Card className={config.ideEnabled ? "" : "opacity-95"}>
      <CardHeader className="space-y-2 pb-4">
        <CardTitle className="flex items-center gap-2">
          <Settings className="h-5 w-5 text-accent" />
          IDE Integration
        </CardTitle>
        <CardDescription>
          Configure how IDE settings are generated and shared with your team
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-8">
        {/* Master IDE toggle */}
        <div className="space-y-4">
          <div className="flex items-start justify-between gap-4 rounded-xl border bg-muted/50 px-5 py-4">
            <div className="space-y-1">
              <p className="text-sm font-medium leading-6">
                Enable IDE integration
              </p>
              <p className="text-sm text-muted-foreground">
                Generate workspace files and settings for the team.
              </p>
            </div>
            <Switch
              checked={config.ideEnabled}
              onCheckedChange={config.setIdeEnabled}
            />
          </div>
        </div>

        {config.ideEnabled && (
          <div className="space-y-6">
            {/* VS Code Section */}
            <div className="space-y-4 rounded-xl border px-5 py-5">
              <div className="flex items-start justify-between gap-4">
                <div className="space-y-1">
                  <h4 className="text-sm font-semibold">VS Code</h4>
                  <p className="text-sm text-muted-foreground">
                    Generate VS Code workspace and settings files.
                  </p>
                </div>
                <Switch
                  checked={config.vscodeEnabled}
                  onCheckedChange={config.setVscodeEnabled}
                />
              </div>

              {config.vscodeEnabled && (
                <div className="space-y-4 border-t pt-4">
                  <div className="space-y-1">
                    <h5 className="text-sm font-medium">
                      Settings output location
                    </h5>
                    <p className="text-sm text-muted-foreground">
                      Choose where VS Code settings are generated.
                    </p>
                  </div>

                  <RadioGroup
                    value={config.vscodeOutputMode}
                    onValueChange={(value) =>
                      config.setVscodeOutputMode(
                        value as "workspace" | "settingsJson",
                      )
                    }
                    className="grid gap-4"
                  >
                    <Label
                      htmlFor="vscode-workspace-mode"
                      className={`group relative flex h-full w-full flex-col items-start gap-3 rounded-lg border bg-card p-4 text-left font-normal leading-normal transition-all hover:border-primary/70 hover:shadow-sm ${
                        isVscodeWorkspaceMode
                          ? "border-primary bg-primary/5 ring-1 ring-primary/30"
                          : "border-border"
                      }`}
                    >
                      <div className="flex items-start gap-3">
                        <RadioGroupItem
                          id="vscode-workspace-mode"
                          value="workspace"
                          className="mt-1"
                        />
                        <div className="space-y-2">
                          <div className="flex flex-wrap items-center gap-2">
                            <FolderOpen className="h-4 w-4 text-blue-500" />
                            <span className="text-sm font-semibold">
                              Workspace file
                            </span>
                            <Badge
                              variant="secondary"
                              className="bg-green-500/20 text-green-800 dark:text-green-200"
                            >
                              Recommended
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground">
                            Generates{" "}
                            <code className="rounded bg-muted px-1">
                              .stackpanel/gen/vscode/stackpanel.code-workspace
                            </code>
                          </p>
                          <p className="text-sm text-muted-foreground">
                            Safe - doesn't modify your existing{" "}
                            <code className="rounded bg-muted px-1">
                              .vscode/settings.json
                            </code>
                            . Open the workspace file in VS Code to use the
                            generated settings.
                          </p>
                        </div>
                      </div>
                    </Label>

                    <Label
                      htmlFor="vscode-settings-json-mode"
                      className={`group relative flex h-full w-full flex-col items-start gap-3 rounded-lg border bg-card p-4 text-left font-normal leading-normal transition-all hover:border-primary/70 hover:shadow-sm ${
                        !isVscodeWorkspaceMode
                          ? "border-primary bg-primary/5 ring-1 ring-primary/30"
                          : "border-border"
                      }`}
                    >
                      <div className="flex items-start gap-3">
                        <RadioGroupItem
                          id="vscode-settings-json-mode"
                          value="settingsJson"
                          className="mt-1"
                        />
                        <div className="space-y-2">
                          <div className="flex flex-wrap items-center gap-2">
                            <FileCode className="h-4 w-4 text-amber-500" />
                            <span className="text-sm font-semibold">
                              Direct settings file
                            </span>
                          </div>
                          <p className="text-sm text-muted-foreground">
                            Generates{" "}
                            <code className="rounded bg-muted px-1">
                              .vscode/settings.json
                            </code>
                          </p>
                          <div className="flex items-start gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-amber-700 dark:text-amber-300">
                            <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                            <p className="text-sm leading-5">
                              Regenerates on each devshell entry. Manual edits
                              will be overwritten.
                            </p>
                          </div>
                        </div>
                      </div>
                    </Label>
                  </RadioGroup>
                </div>
              )}
            </div>

            {/* Zed Section */}
            <div className="space-y-4 rounded-xl border px-5 py-5">
              <div className="flex items-start justify-between gap-4">
                <div className="space-y-1">
                  <h4 className="text-sm font-semibold">Zed</h4>
                  <p className="text-sm text-muted-foreground">
                    Generate Zed editor settings files.
                  </p>
                </div>
                <Switch
                  checked={config.zedEnabled}
                  onCheckedChange={config.setZedEnabled}
                />
              </div>

              {config.zedEnabled && (
                <div className="space-y-4 border-t pt-4">
                  <div className="space-y-1">
                    <h5 className="text-sm font-medium">
                      Settings output location
                    </h5>
                    <p className="text-sm text-muted-foreground">
                      Choose where Zed settings are generated.
                    </p>
                  </div>

                  <RadioGroup
                    value={config.zedOutputMode}
                    onValueChange={(value) =>
                      config.setZedOutputMode(value as "generated" | "dotZed")
                    }
                    className="grid gap-4"
                  >
                    <Label
                      htmlFor="zed-generated-mode"
                      className={`group relative flex h-full w-full flex-col items-start gap-3 rounded-lg border bg-card p-4 text-left font-normal leading-normal transition-all hover:border-primary/70 hover:shadow-sm ${
                        isZedGeneratedMode
                          ? "border-primary bg-primary/5 ring-1 ring-primary/30"
                          : "border-border"
                      }`}
                    >
                      <div className="flex items-start gap-3">
                        <RadioGroupItem
                          id="zed-generated-mode"
                          value="generated"
                          className="mt-1"
                        />
                        <div className="space-y-2">
                          <div className="flex flex-wrap items-center gap-2">
                            <FolderOpen className="h-4 w-4 text-blue-500" />
                            <span className="text-sm font-semibold">
                              Generated directory
                            </span>
                            <Badge
                              variant="secondary"
                              className="bg-green-500/20 text-green-800 dark:text-green-200"
                            >
                              Recommended
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground">
                            Generates{" "}
                            <code className="rounded bg-muted px-1">
                              .stackpanel/gen/zed/settings.json
                            </code>
                          </p>
                          <p className="text-sm text-muted-foreground">
                            Safe - doesn't modify your existing{" "}
                            <code className="rounded bg-muted px-1">.zed/</code>{" "}
                            directory. Symlink{" "}
                            <code className="rounded bg-muted px-1">
                              .zed -&gt; .stackpanel/gen/zed
                            </code>{" "}
                            to use.
                          </p>
                        </div>
                      </div>
                    </Label>

                    <Label
                      htmlFor="zed-dotzed-mode"
                      className={`group relative flex h-full w-full flex-col items-start gap-3 rounded-lg border bg-card p-4 text-left font-normal leading-normal transition-all hover:border-primary/70 hover:shadow-sm ${
                        !isZedGeneratedMode
                          ? "border-primary bg-primary/5 ring-1 ring-primary/30"
                          : "border-border"
                      }`}
                    >
                      <div className="flex items-start gap-3">
                        <RadioGroupItem
                          id="zed-dotzed-mode"
                          value="dotZed"
                          className="mt-1"
                        />
                        <div className="space-y-2">
                          <div className="flex flex-wrap items-center gap-2">
                            <FileCode className="h-4 w-4 text-amber-500" />
                            <span className="text-sm font-semibold">
                              Direct .zed directory
                            </span>
                          </div>
                          <p className="text-sm text-muted-foreground">
                            Generates{" "}
                            <code className="rounded bg-muted px-1">
                              .zed/settings.json
                            </code>
                          </p>
                          <div className="flex items-start gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-amber-700 dark:text-amber-300">
                            <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                            <p className="text-sm leading-5">
                              Regenerates on each devshell entry. Manual edits
                              will be overwritten.
                            </p>
                          </div>
                        </div>
                      </div>
                    </Label>
                  </RadioGroup>
                </div>
              )}
            </div>
          </div>
        )}

        <div className="flex justify-end border-t pt-4">
          <Button onClick={config.saveIde} disabled={config.savingIde}>
            {config.savingIde ? "Saving..." : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

// Keep backward compatibility export
export { IdeSection as VscodeSection };
