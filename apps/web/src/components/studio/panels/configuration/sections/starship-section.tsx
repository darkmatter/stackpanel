"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Label } from "@ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import { Terminal } from "lucide-react";
import { STARSHIP_PRESETS } from "../constants";
import type { UseConfigurationResult } from "../use-configuration";

interface StarshipSectionProps {
  config: UseConfigurationResult;
}

export function StarshipSection({ config }: StarshipSectionProps) {
  return (
    <Card className={config.themeEnabled ? "" : "opacity-95"}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Terminal className="h-5 w-5 text-accent" />
          Starship Prompt
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Enable prompt theme</p>
            <p className="text-muted-foreground text-xs">
              Apply the shared Starship theme for your shell
            </p>
          </div>
          <Switch
            checked={config.themeEnabled}
            onCheckedChange={config.setThemeEnabled}
          />
        </div>
        <div className="grid gap-2">
          <Label>Preset</Label>
          <Select
            value={config.themePreset}
            onValueChange={config.setThemePreset}
          >
            <SelectTrigger>
              <SelectValue placeholder="Choose a preset" />
            </SelectTrigger>
            <SelectContent>
              {STARSHIP_PRESETS.map((preset) => (
                <SelectItem key={preset.value} value={preset.value}>
                  {preset.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="flex justify-end">
          <Button onClick={config.saveTheme} disabled={config.savingTheme}>
            {config.savingTheme ? "Saving..." : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
