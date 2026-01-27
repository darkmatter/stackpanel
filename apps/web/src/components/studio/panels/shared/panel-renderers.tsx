"use client";

/**
 * Shared panel renderers for STATUS, APPS_GRID, APP_CONFIG, and generic panels.
 *
 * Used by both the top-level Panels screen and the per-app Modules tab.
 */

import { Badge } from "@ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Label } from "@ui/label";
import { AlertCircle, CheckCircle } from "lucide-react";
import { cn } from "@/lib/utils";
import { usePatchNixData } from "@/lib/use-agent";
import type {
  AppConfigField,
  AppModulePanel,
  MetricItem,
  NixPanel,
} from "./panel-types";
import { FieldRenderer } from "./field-renderer";
import { FieldDisplay } from "./field-display";

// =============================================================================
// Status Panel
// =============================================================================

export function StatusPanelRenderer({ panel }: { panel: NixPanel }) {
  const metricsField = panel.fields.find((f) => f.name === "metrics");

  let metrics: MetricItem[] = [];
  if (metricsField?.value) {
    try {
      metrics = JSON.parse(metricsField.value);
    } catch {
      // Not valid JSON, skip
    }
  }

  const otherFields = panel.fields.filter((f) => f.name !== "metrics");

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-medium flex items-center gap-2">
          {panel.title}
          {panel.description && (
            <span className="text-xs text-muted-foreground font-normal">
              {panel.description}
            </span>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {metrics.length > 0 && (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            {metrics.map((metric) => (
              <div
                key={metric.label}
                className="rounded-lg border bg-card p-3 space-y-1"
              >
                <div className="flex items-center gap-1.5">
                  {metric.status === "ok" && (
                    <CheckCircle className="h-3 w-3 text-green-500" />
                  )}
                  {metric.status === "warn" && (
                    <AlertCircle className="h-3 w-3 text-yellow-500" />
                  )}
                  {metric.status === "error" && (
                    <AlertCircle className="h-3 w-3 text-red-500" />
                  )}
                  <span className="text-xs text-muted-foreground">
                    {metric.label}
                  </span>
                </div>
                <div className="text-sm font-medium">{metric.value}</div>
              </div>
            ))}
          </div>
        )}

        {otherFields.map((field) => (
          <FieldDisplay key={field.name} field={field} />
        ))}
      </CardContent>
    </Card>
  );
}

// =============================================================================
// Apps Grid Panel
// =============================================================================

export function AppsGridPanelRenderer({ panel }: { panel: NixPanel }) {
  const apps = Object.entries(panel.apps);

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-medium">{panel.title}</CardTitle>
      </CardHeader>
      <CardContent>
        {apps.length === 0 ? (
          <p className="text-xs text-muted-foreground">No apps configured</p>
        ) : (
          <div className="space-y-1.5">
            {apps.map(([appName, appData]) => (
              <div
                key={appName}
                className="flex items-center gap-3 rounded-md border px-3 py-2"
              >
                <div
                  className={cn(
                    "h-2 w-2 rounded-full",
                    appData.enabled ? "bg-green-500" : "bg-muted",
                  )}
                />
                <span className="text-sm font-medium">{appName}</span>
                <div className="flex-1" />
                {Object.entries(appData.config).map(([key, val]) => (
                  <Badge
                    key={key}
                    variant="outline"
                    className="text-xs font-mono"
                  >
                    {key}: {val}
                  </Badge>
                ))}
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// =============================================================================
// App Config Form — editable per-app config for a single module panel
// =============================================================================

export function AppConfigFormRenderer({
  panel,
  appId,
  disabled,
}: {
  panel: AppModulePanel;
  appId: string;
  disabled?: boolean;
}) {
  const patchNixData = usePatchNixData();
  const appData = panel.apps[appId];

  if (!appData) return null;

  const handleFieldChange = (field: AppConfigField, newValue: string) => {
    if (!field.editPath || !field.editable) return;

    let valueType = "string";
    if (field.type === "FIELD_TYPE_BOOLEAN") valueType = "bool";
    else if (field.type === "FIELD_TYPE_NUMBER") valueType = "number";
    else if (field.type === "FIELD_TYPE_MULTISELECT") valueType = "list";
    else if (field.type === "FIELD_TYPE_JSON") valueType = "object";

    const jsonValue =
      valueType === "string" ? JSON.stringify(newValue) : newValue;

    patchNixData.mutate({
      entity: "apps",
      key: appId,
      path: field.editPath,
      value: jsonValue,
      valueType,
    });
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <h4 className="text-xs font-medium text-foreground">{panel.title}</h4>
        <Badge variant="outline" className="text-[10px] px-1.5 py-0">
          {panel.module}
        </Badge>
      </div>

      <div className="space-y-2">
        {panel.fields.map((field) => {
          const currentValue = appData.config[field.name] ?? "";

          return (
            <div key={field.name} className="space-y-1">
              <Label className="text-xs text-muted-foreground">
                {field.label ?? field.name}
              </Label>
              <FieldRenderer
                field={field}
                value={currentValue}
                disabled={disabled || !field.editable}
                isSaving={patchNixData.isPending}
                onChange={(val) => handleFieldChange(field, val)}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}

// =============================================================================
// Generic Panel Renderer — dispatches to type-specific renderers
// =============================================================================

export function PanelRenderer({ panel }: { panel: NixPanel }) {
  switch (panel.type) {
    case "PANEL_TYPE_STATUS":
      return <StatusPanelRenderer panel={panel} />;
    case "PANEL_TYPE_APPS_GRID":
      return <AppsGridPanelRenderer panel={panel} />;
    case "PANEL_TYPE_FORM":
    case "PANEL_TYPE_TABLE":
    case "PANEL_TYPE_CUSTOM":
    default:
      // Generic fallback: render all fields as display
      return (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">
              {panel.title}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {panel.fields.map((field) => (
              <FieldDisplay key={field.name} field={field} />
            ))}
          </CardContent>
        </Card>
      );
  }
}
