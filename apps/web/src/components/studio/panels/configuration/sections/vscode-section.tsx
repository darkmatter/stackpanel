"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Switch } from "@ui/switch";
import { Settings } from "lucide-react";
import type { UseConfigurationResult } from "../use-configuration";

interface VscodeSectionProps {
  config: UseConfigurationResult;
}

export function VscodeSection({ config }: VscodeSectionProps) {
  return (
    <Card className={config.ideEnabled ? "" : "opacity-95"}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Settings className="h-5 w-5 text-accent" />
          VS Code Integration
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Enable IDE integration</p>
            <p className="text-muted-foreground text-xs">
              Generate workspace files and settings for the team
            </p>
          </div>
          <Switch
            checked={config.ideEnabled}
            onCheckedChange={config.setIdeEnabled}
          />
        </div>
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">VS Code workspace</p>
            <p className="text-muted-foreground text-xs">
              Include VS Code settings in generated files
            </p>
          </div>
          <Switch
            checked={config.vscodeEnabled}
            onCheckedChange={config.setVscodeEnabled}
          />
        </div>
        <div className="flex justify-end">
          <Button onClick={config.saveIde} disabled={config.savingIde}>
            {config.savingIde ? "Saving..." : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
