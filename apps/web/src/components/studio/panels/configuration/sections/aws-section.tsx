"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Lock } from "lucide-react";
import type { UseConfigurationResult } from "../use-configuration";

interface AwsSectionProps {
  config: UseConfigurationResult;
}

export function AwsSection({ config }: AwsSectionProps) {
  return (
    <Card className={config.awsEnabled ? "" : "opacity-95"}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Lock className="h-5 w-5 text-accent" />
          AWS Roles Anywhere
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Enable AWS auth</p>
            <p className="text-muted-foreground text-xs">
              Use cert-based authentication for AWS
            </p>
          </div>
          <Switch
            checked={config.awsEnabled}
            onCheckedChange={config.setAwsEnabled}
          />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2">
            <Label htmlFor="aws-region">Region</Label>
            <Input
              id="aws-region"
              placeholder="us-west-2"
              value={config.awsRegion}
              onChange={(event) => config.setAwsRegion(event.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="aws-account">Account ID</Label>
            <Input
              id="aws-account"
              placeholder="123456789"
              value={config.awsAccountId}
              onChange={(event) => config.setAwsAccountId(event.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="aws-role">Role name</Label>
            <Input
              id="aws-role"
              placeholder="developer"
              value={config.awsRoleName}
              onChange={(event) => config.setAwsRoleName(event.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="aws-cache-buffer">Cache buffer (seconds)</Label>
            <Input
              id="aws-cache-buffer"
              placeholder="300"
              value={config.awsCacheBufferSeconds}
              onChange={(event) =>
                config.setAwsCacheBufferSeconds(event.target.value)
              }
            />
          </div>
          <div className="grid gap-2 sm:col-span-2">
            <Label htmlFor="aws-trust-anchor">Trust anchor ARN</Label>
            <Input
              id="aws-trust-anchor"
              placeholder="arn:aws:rolesanywhere:..."
              value={config.awsTrustAnchorArn}
              onChange={(event) =>
                config.setAwsTrustAnchorArn(event.target.value)
              }
            />
          </div>
          <div className="grid gap-2 sm:col-span-2">
            <Label htmlFor="aws-profile-arn">Profile ARN</Label>
            <Input
              id="aws-profile-arn"
              placeholder="arn:aws:rolesanywhere:..."
              value={config.awsProfileArn}
              onChange={(event) => config.setAwsProfileArn(event.target.value)}
            />
          </div>
        </div>
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Prompt on shell entry</p>
            <p className="text-muted-foreground text-xs">
              Ask users to finish AWS auth if missing
            </p>
          </div>
          <Switch
            checked={config.awsPromptOnShell}
            onCheckedChange={config.setAwsPromptOnShell}
          />
        </div>
        <div className="flex justify-end">
          <Button onClick={config.saveAws} disabled={config.savingAws}>
            {config.savingAws ? "Saving..." : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
