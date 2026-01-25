"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Plus, Trash2 } from "lucide-react";
import { useState } from "react";
import type { ProcessComposeSettings } from "./types";

interface ProcessSettingsProps {
  settings: ProcessComposeSettings;
  onUpdate: (updates: Partial<ProcessComposeSettings>) => void;
}

export function ProcessSettings({ settings, onUpdate }: ProcessSettingsProps) {
  const [newEnvKey, setNewEnvKey] = useState("");
  const [newEnvValue, setNewEnvValue] = useState("");

  const handleAddEnvVar = () => {
    if (!newEnvKey) return;
    onUpdate({
      environment: {
        ...settings.environment,
        [newEnvKey]: newEnvValue,
      },
    });
    setNewEnvKey("");
    setNewEnvValue("");
  };

  const handleRemoveEnvVar = (key: string) => {
    const { [key]: _, ...rest } = settings.environment;
    onUpdate({ environment: rest });
  };

  const handleExtensionChange = (extensions: string[]) => {
    onUpdate({
      formatWatcher: {
        ...settings.formatWatcher,
        extensions,
      },
    });
  };

  return (
    <div className="space-y-6">
      {/* Command Name */}
      <div className="grid gap-2">
        <Label htmlFor="commandName">Command Name</Label>
        <div className="flex gap-2">
          <Input
            id="commandName"
            value={settings.commandName}
            onChange={(e) => onUpdate({ commandName: e.target.value })}
            placeholder="dev"
            className="max-w-[200px]"
          />
          <p className="text-xs text-muted-foreground self-center">
            The command to start all processes (e.g., <code>$ {settings.commandName}</code>)
          </p>
        </div>
      </div>

      {/* Format Watcher */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="space-y-0.5">
            <Label>Format Watcher</Label>
            <p className="text-xs text-muted-foreground">
              Automatically run formatter when files change
            </p>
          </div>
          <Switch
            checked={settings.formatWatcher.enable}
            onCheckedChange={(enable) =>
              onUpdate({
                formatWatcher: { ...settings.formatWatcher, enable },
              })
            }
          />
        </div>

        {settings.formatWatcher.enable && (
          <div className="grid gap-2 pl-4 border-l-2 border-secondary">
            <Label htmlFor="extensions">File Extensions</Label>
            <div className="flex flex-wrap gap-1">
              {settings.formatWatcher.extensions.map((ext) => (
                <Badge
                  key={ext}
                  variant="secondary"
                  className="cursor-pointer hover:bg-destructive/20"
                  onClick={() =>
                    handleExtensionChange(
                      settings.formatWatcher.extensions.filter((e) => e !== ext)
                    )
                  }
                >
                  .{ext}
                  <Trash2 className="ml-1 h-3 w-3" />
                </Badge>
              ))}
            </div>
            <div className="flex gap-2 mt-2">
              <Input
                id="extensions"
                placeholder="Add extension (e.g., yaml)"
                className="max-w-[200px]"
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    const input = e.currentTarget;
                    const ext = input.value.replace(/^\./, "").trim();
                    if (ext && !settings.formatWatcher.extensions.includes(ext)) {
                      handleExtensionChange([...settings.formatWatcher.extensions, ext]);
                      input.value = "";
                    }
                  }
                }}
              />
              <p className="text-xs text-muted-foreground self-center">
                Press Enter to add
              </p>
            </div>

            <div className="mt-2">
              <Label htmlFor="formatCommand">Format Command (optional)</Label>
              <Input
                id="formatCommand"
                value={settings.formatWatcher.command ?? ""}
                onChange={(e) =>
                  onUpdate({
                    formatWatcher: {
                      ...settings.formatWatcher,
                      command: e.target.value || undefined,
                    },
                  })
                }
                placeholder="turbo run format --continue"
                className="mt-1"
              />
              <p className="text-xs text-muted-foreground mt-1">
                Leave empty to use default: <code>turbo run format --continue</code>
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Global Environment Variables */}
      <div className="space-y-4">
        <div>
          <Label>Global Environment Variables</Label>
          <p className="text-xs text-muted-foreground">
            Environment variables passed to all processes
          </p>
        </div>

        {Object.keys(settings.environment).length > 0 && (
          <div className="space-y-2">
            {Object.entries(settings.environment).map(([key, value]) => (
              <div key={key} className="flex items-center gap-2">
                <code className="text-sm bg-secondary px-2 py-1 rounded">
                  {key}
                </code>
                <span className="text-muted-foreground">=</span>
                <code className="text-sm bg-secondary px-2 py-1 rounded flex-1 truncate">
                  {value}
                </code>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-muted-foreground hover:text-destructive"
                  onClick={() => handleRemoveEnvVar(key)}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
            ))}
          </div>
        )}

        <div className="flex gap-2">
          <Input
            placeholder="KEY"
            value={newEnvKey}
            onChange={(e) => setNewEnvKey(e.target.value.toUpperCase())}
            className="max-w-[150px]"
          />
          <span className="self-center text-muted-foreground">=</span>
          <Input
            placeholder="value"
            value={newEnvValue}
            onChange={(e) => setNewEnvValue(e.target.value)}
            className="flex-1"
          />
          <Button
            variant="outline"
            size="icon"
            onClick={handleAddEnvVar}
            disabled={!newEnvKey}
          >
            <Plus className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </div>
  );
}
