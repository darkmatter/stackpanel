"use client";

import React, { useMemo } from "react";
import { Copy, Sparkles, TriangleAlert } from "lucide-react";
import { Button } from "@ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@ui/card";
import { Label } from "@ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Separator } from "@ui/separator";
import { Switch } from "@ui/switch";
import { FEATURE_FLAG_KEYS, useFeatureFlags } from "@gen/featureflags";
import { cn } from "@/lib/utils";

function buildQuerySnippet(overrides: Record<string, string>): string {
  const entries = Object.entries(overrides);
  if (!entries.length) {
    return "";
  }

  return `ff=${entries
    .map(([key, value]) => `${key}=${encodeURIComponent(value)}`)
    .join(",")}`;
}

function getStatusClass(isOverridden: boolean, isEnabled: boolean | null = null): string {
  if (!isOverridden) {
    return "bg-secondary text-muted-foreground";
  }

  if (isEnabled === false) {
    return "bg-amber-500/10 text-amber-300";
  }

  return "bg-emerald-500/10 text-emerald-300";
}

export function FeatureFlagsPanel() {
  const {
    definitions,
    isEnabled,
    getVariant,
    getValue,
    setOverride,
    clearOverride,
    clearAllOverrides,
    localOverrides,
    isOverridden,
    identity,
  } = useFeatureFlags();

  const querySnippet = buildQuerySnippet(localOverrides);
  const hasOverrides = Object.keys(localOverrides).length > 0;
  const originPath = useMemo(() => {
    if (typeof window === "undefined") {
      return "";
    }

    return `${window.location.origin}/studio/feature-flags`;
  }, []);

  const shareUrl = useMemo(() => {
    if (!originPath) {
      return "/studio/feature-flags";
    }

    return querySnippet ? `${originPath}?${querySnippet}` : originPath;
  }, [originPath, querySnippet]);

  const copyUrl = async () => {
    const copied = await Promise.resolve().then(async () => {
      if (!hasOverrides) {
        if (typeof navigator === "undefined" || typeof navigator.clipboard?.writeText !== "function") {
          return false;
        }

        try {
          await navigator.clipboard.writeText(shareUrl);
          return true;
        } catch {
          return false;
        }
      }

      if (typeof window === "undefined") {
        return false;
      }

      const nextUrl = `${originPath}?${querySnippet}`;
      if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
        try {
          await navigator.clipboard.writeText(nextUrl);
          return true;
        } catch {
          return false;
        }
      }

      return false;
    });

    if (!copied && typeof window !== "undefined") {
      window.prompt("Copy this URL:", shareUrl);
    }
  };

  const copyLabel = querySnippet.length > 0 ? "Copy override URL" : "Copy page URL";
  const queryLabel = querySnippet
    ? `ff query: ?${querySnippet}`
    : "No query overrides are active";
  const copyHelpText = querySnippet
    ? "Share this URL to reproduce the same local overrides."
    : "Share the base feature flag endpoint.";

  const examples = useMemo(
    () =>
      `?ff_${FEATURE_FLAG_KEYS.overviewLayout}=compact&ff_${
        FEATURE_FLAG_KEYS.overviewPulseBanner
      }=true`,
    [],
  );

  return (
    <div className="space-y-6">
      <Card className="border-accent/30">
        <CardHeader>
          <div className="flex flex-wrap items-center gap-2">
            <Sparkles className="h-4 w-4 text-accent" />
            <CardTitle>Studio Feature Flags</CardTitle>
          </div>
          <CardDescription>
            Runtime feature experiments for Studio with deterministic rollout and
            local overrides.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-1">
            <div className="text-xs uppercase tracking-wide text-muted-foreground">
              Browser identity
            </div>
            <p className="rounded-md bg-secondary px-3 py-2 text-xs font-mono break-all">
              {identity}
            </p>
          </div>

          <Separator />

          <div className="space-y-1">
            <div className="text-xs uppercase tracking-wide text-muted-foreground">
              URL override examples
            </div>
            <p className="rounded-md bg-secondary px-3 py-2 text-xs font-mono break-all">
              {queryLabel}
            </p>
            <p className="rounded-md bg-secondary px-3 py-2 text-xs font-mono break-all">
              {examples}
            </p>
          </div>

          <div className="flex flex-wrap gap-2">
            <Button onClick={copyUrl} size="sm">
              <Copy className="mr-2 h-4 w-4" />
              {copyLabel}
            </Button>
            <Button
              onClick={clearAllOverrides}
              size="sm"
              variant="outline"
              disabled={!hasOverrides}
            >
              Clear all local overrides
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Current override state</CardTitle>
          <CardDescription>
            {hasOverrides
              ? `Active overrides: ${querySnippet}`
              : "No local overrides are set. Add controls above to pin values."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-muted-foreground">{copyHelpText}</p>
          <p className="mt-2 rounded-md bg-secondary px-3 py-2 text-xs font-mono break-all">
            {shareUrl}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Available Flags</CardTitle>
          <CardDescription>
            Toggle or set values below to test Studio experiments.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          {definitions.map((definition) => {
            const override = isOverridden(definition.key);
            const statusClasses = getStatusClass(
              override,
              definition.kind === "boolean" ? isEnabled(definition.key) : true,
            );

            if (definition.kind === "boolean") {
              const enabled = isEnabled(definition.key);
              return (
                <div
                  key={definition.key}
                  className={cn("rounded-lg border p-4", statusClasses, "transition-colors")}
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="space-y-1">
                      <h3 className="font-medium">{definition.label}</h3>
                      <p className="text-muted-foreground text-sm">
                        {definition.description}
                      </p>
                      <p className="text-xs font-mono text-muted-foreground">
                        {definition.key}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      {override && (
                        <span className="rounded-full border border-border px-2 py-1 text-xs">
                          local override
                        </span>
                      )}
                      <Label htmlFor={definition.key} className="sr-only">
                        {definition.label}
                      </Label>
                      <Switch
                        id={definition.key}
                        checked={enabled}
                        onCheckedChange={(value) => setOverride(definition.key, value)}
                      />
                      <Button
                        onClick={() => clearOverride(definition.key)}
                        size="sm"
                        variant="ghost"
                        disabled={!override}
                      >
                        Undo
                      </Button>
                    </div>
                  </div>
                </div>
              );
            }

            const selected = getVariant(definition.key, definition.defaultValue);
            return (
              <div
                key={definition.key}
                className={cn("rounded-lg border p-4", statusClasses, "transition-colors")}
              >
                <div className="space-y-3">
                  <div className="flex items-start justify-between gap-4">
                    <div className="space-y-1">
                      <h3 className="font-medium">{definition.label}</h3>
                      <p className="text-muted-foreground text-sm">
                        {definition.description}
                      </p>
                      <p className="text-xs font-mono text-muted-foreground">
                        {definition.key}
                      </p>
                    </div>
                    {override && (
                      <span className="rounded-full border border-border px-2 py-1 text-xs h-fit">
                        local override
                      </span>
                    )}
                  </div>
                  <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-center">
                    <div>
                      <Label className="text-xs text-muted-foreground">Variant</Label>
                      <p className="text-sm">
                        Effective value: <span className="font-mono">{selected}</span>
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Select
                        value={selected}
                        onValueChange={(value) => setOverride(definition.key, value)}
                      >
                        <SelectTrigger className="w-56">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {definition.variants.map((variant) => (
                            <SelectItem key={variant} value={variant}>
                              {variant}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Button
                        onClick={() => clearOverride(definition.key)}
                        size="sm"
                        variant="ghost"
                        disabled={!override}
                      >
                        Undo
                      </Button>
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Active value: <span className="font-mono">{getValue(definition.key) as string}</span>
                  </p>
                </div>
              </div>
            );
          })}
        </CardContent>
      </Card>

      {!hasOverrides ? (
        <Card>
          <CardContent className="flex items-start gap-3 text-sm text-muted-foreground py-4">
            <TriangleAlert className="mt-0.5 h-4 w-4 text-amber-400" />
            <p>
              No local overrides are set. Use the controls above or URL parameters
              for temporary sessions.
            </p>
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}
