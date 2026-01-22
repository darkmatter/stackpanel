"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { AlertCircle, Loader2, RefreshCw, Shield } from "lucide-react";
import type { UseConfigurationResult } from "../use-configuration";

interface StepCaSectionProps {
  config: UseConfigurationResult;
}

export function StepCaSection({ config }: StepCaSectionProps) {
  return (
    <Card className={config.stepEnabled ? "" : "opacity-95"}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Shield className="h-5 w-5 text-accent" />
          Step CA
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Enable Step CA</p>
            <p className="text-muted-foreground text-xs">
              Issue local TLS certificates for your team
            </p>
          </div>
          <Switch
            checked={config.stepEnabled}
            onCheckedChange={config.setStepEnabled}
          />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2">
            <Label htmlFor="step-ca-url">CA URL</Label>
            <Input
              id="step-ca-url"
              placeholder="https://ca.internal:443"
              value={config.stepCaUrl}
              onChange={(event) => config.setStepCaUrl(event.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="step-ca-fingerprint">CA Fingerprint</Label>
            <div className="flex gap-2">
              <Input
                id="step-ca-fingerprint"
                placeholder="SHA256 fingerprint"
                value={config.stepCaFingerprint}
                onChange={(event) =>
                  config.setStepCaFingerprint(event.target.value)
                }
                className="flex-1"
              />
              <Button
                type="button"
                variant="outline"
                size="icon"
                onClick={config.fetchFingerprint}
                disabled={!config.stepCaUrl || config.fetchingFingerprint}
                title="Fetch fingerprint from CA"
              >
                {config.fetchingFingerprint ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <RefreshCw className="h-4 w-4" />
                )}
              </Button>
            </div>
            {config.stepCaUrl && !config.stepCaFingerprint && (
              <p className="text-xs text-muted-foreground">
                Enter a CA URL and click refresh to fetch the fingerprint
              </p>
            )}
            {config.stepCaError && (
              <div className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs text-destructive">
                <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                <p className="leading-5">{config.stepCaError}</p>
              </div>
            )}
          </div>
          <div className="grid gap-2">
            <Label htmlFor="step-ca-provisioner">Provisioner</Label>
            <Input
              id="step-ca-provisioner"
              placeholder="Provisioner name"
              value={config.stepProvisioner}
              onChange={(event) =>
                config.setStepProvisioner(event.target.value)
              }
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="step-ca-cert">Certificate Name</Label>
            <Input
              id="step-ca-cert"
              placeholder="device"
              value={config.stepCertName}
              onChange={(event) => config.setStepCertName(event.target.value)}
            />
          </div>
        </div>
        <div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
          <div>
            <p className="font-medium text-sm">Prompt on shell entry</p>
            <p className="text-muted-foreground text-xs">
              Remind users to set up certificates if missing
            </p>
          </div>
          <Switch
            checked={config.stepPromptOnShell}
            onCheckedChange={config.setStepPromptOnShell}
          />
        </div>
        <div className="flex justify-end">
          <Button onClick={config.saveStepCa} disabled={config.savingStepCa}>
            {config.savingStepCa ? "Saving..." : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
