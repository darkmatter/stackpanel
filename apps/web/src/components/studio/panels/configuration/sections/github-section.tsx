"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Github } from "lucide-react";
import type { UseConfigurationResult } from "../use-configuration";

interface GitHubSectionProps {
  config: UseConfigurationResult;
}

export function GitHubSection({ config }: GitHubSectionProps) {
  const isConfigured = config.githubRepo.trim() && config.githubSyncEnabled;

  return (
    <Card className={isConfigured ? "" : "opacity-95"}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Github className="h-5 w-5 text-accent" />
          GitHub
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-2">
          <Label htmlFor="github-repo">Repository</Label>
          <Input
            id="github-repo"
            placeholder="owner/repo"
            value={config.githubRepo}
            onChange={(event) => config.setGithubRepo(event.target.value)}
          />
        </div>
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">GitHub user sync</p>
            <p className="text-muted-foreground text-xs">
              Sync collaborators and public keys from the repository
            </p>
          </div>
          <Switch
            className="data-[state=checked]:bg-accent"
            checked={config.githubSyncEnabled}
            onCheckedChange={config.setGithubSyncEnabled}
          />
        </div>
        <div className="flex justify-end">
          <Button onClick={config.saveGithub} disabled={config.savingGithub}>
            {config.savingGithub ? "Saving..." : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
