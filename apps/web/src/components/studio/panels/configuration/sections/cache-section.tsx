"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { AlertTriangle, Check, Shield } from "lucide-react";
import type { UseConfigurationResult } from "../use-configuration";

interface CacheSectionProps {
  config: UseConfigurationResult;
}

export function CacheSection({ config }: CacheSectionProps) {
  return (
    <Card className={config.cacheEnabled ? "" : "opacity-95"}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Shield className="h-5 w-5 text-accent" />
          Binary Cache (Cachix)
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {!config.secretsEnabled && (
          <div className="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-600 dark:text-amber-400">
            <AlertTriangle className="mt-0.5 h-4 w-4" />
            <p>
              Secrets must be enabled before configuring Cachix push tokens.
            </p>
          </div>
        )}
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Enable binary cache</p>
            <p className="text-muted-foreground text-xs">
              Use Cachix to speed up local builds
            </p>
          </div>
          <Switch
            checked={config.cacheEnabled}
            onCheckedChange={config.setCacheEnabled}
          />
        </div>
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Push to Cachix</p>
            <p className="text-muted-foreground text-xs">
              Upload build artifacts to a shared cache
            </p>
          </div>
          <Switch
            checked={config.cachixEnabled}
            onCheckedChange={config.setCachixEnabled}
            disabled={!config.cacheEnabled || !config.secretsEnabled}
          />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2">
            <Label htmlFor="cachix-cache">Cachix cache name</Label>
            <Input
              id="cachix-cache"
              placeholder="my-cache"
              value={config.cachixCache}
              onChange={(event) => config.setCachixCache(event.target.value)}
              disabled={!config.cacheEnabled}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="cachix-token">Cachix token path</Label>
            <Input
              id="cachix-token"
              placeholder=".stack/secrets/cachix.token"
              value={config.cachixTokenPath}
              onChange={(event) =>
                config.setCachixTokenPath(event.target.value)
              }
              disabled={config.cachixControlsDisabled}
            />
          </div>
        </div>
        <div className="flex justify-between text-xs text-muted-foreground">
          <div className="flex items-center gap-2">
            <Badge variant="secondary">Secrets</Badge>
            <span>{config.secretsEnabled ? "Enabled" : "Disabled"}</span>
          </div>
          <div className="flex items-center gap-2">
            {config.cacheEnabled && config.cachixEnabled ? (
              <Check className="h-4 w-4 text-green-500" />
            ) : null}
            <span>
              {config.cachixControlsDisabled
                ? "Enable secrets and cache to push"
                : "Ready for Cachix push"}
            </span>
          </div>
        </div>
        <div className="flex justify-end">
          <Button onClick={config.saveCache} disabled={config.savingCache}>
            {config.savingCache ? "Saving..." : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
