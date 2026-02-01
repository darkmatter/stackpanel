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
import { EditableFieldGroup, type EditableFieldItem } from "./editable-field";
import { FieldGroup } from '@stackpanel/ui-web/field';

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
// Form Panel - renders editable configuration fields using EditableFieldGroup
// =============================================================================

export function FormPanelRenderer({ panel }: { panel: NixPanel }) {
  // Convert NixPanel fields to EditableFieldItem format
  const fieldItems: EditableFieldItem[] = panel.fields.map((field) => ({
    field: {
      name: field.name,
      type: field.type,
      label: field.label,
      placeholder: field.placeholder,
      description: field.description,
      options: field.options,
    },
    initialValue: field.value ?? "",
    configPath: field.configPath,
    editPath: field.editPath,
  }));

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
      <CardContent>
        <EditableFieldGroup fields={fieldItems} />
      </CardContent>
    </Card>
  );
}

// =============================================================================
// Table Panel - renders tabular data with columns and rows
// =============================================================================

export function TablePanelRenderer({ panel }: { panel: NixPanel }) {
  const columns = panel.columns ?? [];
  const rows = panel.rows ?? [];

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
      <CardContent>
        {rows.length === 0 ? (
          <p className="text-xs text-muted-foreground">No data available</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b">
                  {columns.map((col) => (
                    <th
                      key={col.key}
                      className="text-left py-2 px-3 text-xs font-medium text-muted-foreground"
                    >
                      {col.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row, idx) => (
                  <tr
                    key={idx}
                    className="border-b last:border-0 hover:bg-muted/50"
                  >
                    {columns.map((col) => (
                      <td key={col.key} className="py-2 px-3 text-xs">
                        {row[col.key] ?? "-"}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
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

      {/* Module documentation */}
      {panel.readme && (
        <div className="text-xs text-muted-foreground bg-muted/30 rounded-md p-3 border border-border/50">
          <div className="prose prose-xs prose-slate dark:prose-invert max-w-none">
            {/* Simple markdown-like rendering: preserve paragraphs and code */}
            {panel.readme.split("\n\n").map((paragraph, i) => {
              // Check if it's a code block
              if (paragraph.startsWith("```")) {
                const code = paragraph.replace(/^```\w*\n?/, "").replace(/```$/, "");
                return (
                  <pre
                    key={i}
                    className="bg-slate-900 text-slate-300 p-2 rounded text-[10px] font-mono overflow-x-auto my-2"
                  >
                    <code>{code}</code>
                  </pre>
                );
              }
              // Regular paragraph
              return (
                <p key={i} className="mb-2 last:mb-0 leading-relaxed">
                  {paragraph}
                </p>
              );
            })}
          </div>
        </div>
      )}

      {/* Form fields with max width constraint */}
      <div className="space-y-3 max-w-md">
        <FieldGroup>

        {panel.fields.map((field) => {
          const currentValue = appData.config[field.name] ?? "";

          return (
            <div key={field.name} className="space-y-1">
              <FieldRenderer
                field={field}
                value={currentValue}
                disabled={disabled || !field.editable}
                isSaving={patchNixData.isPending}
                onChange={(val) => handleFieldChange(field, val)}
              />
              {/* Help text: description and/or example */}
              {/* {(field.description || field.example) && (
                <div className="text-[10px] text-muted-foreground/70 leading-relaxed">
                  {field.description && <p>{field.description}</p>}
                  {field.example && (
                    <p className="font-mono mt-0.5">
                      Example: <span className="text-muted-foreground">{field.example}</span>
                    </p>
                  )}
                </div>
              )} */}
            </div>
          );
        })}
        </FieldGroup>
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
      return <FormPanelRenderer panel={panel} />;
    case "PANEL_TYPE_TABLE":
      return <TablePanelRenderer panel={panel} />;
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
