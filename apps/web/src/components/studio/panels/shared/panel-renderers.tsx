"use client";

import type { JsonValue } from "@bufbuild/protobuf";
import { FieldGroup } from "@stackpanel/ui-web/field";
import { Badge } from "@ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { AlertCircle, CheckCircle } from "lucide-react";
import { useState } from "react";
import { usePatchNixData } from "@/lib/use-agent";
import { useModuleQueryScope } from "../modules/use-modules";
import { EditableFieldGroup } from "./editable-field";
import { FieldDisplay } from "./field-display";
import { FieldRenderer } from "./field-renderer";
import { ModuleMarkdown } from "./module-markdown";
import { getModuleIconByName } from "./module-icons";
import { ActionButtons, PanelActionScope } from "./panel-action-bar";
import { displayCell, statusMetrics, tableData } from "./panel-data";
import type { MetricItem, NixPanel } from "./panel-types";
import { SandboxedCustomPanel } from "./sandboxed-custom-panel";
import { SpecPanel } from "./spec/spec-panel";
import { studioPanelMatchesApp } from "./use-studio-panels";

type PanelProps = { panel: NixPanel; appId?: string };
type CatalogPanelProps = PanelProps & { panels: readonly NixPanel[] };
type PanelTreeProps = CatalogPanelProps & { ancestors: readonly string[] };
type DataResult = { value: JsonValue | undefined };

export function StatusPanelRenderer({ panel, result }: PanelProps & { result?: DataResult }) {
  const metricField = panel.fields.find(
    (field) =>
      field.name === "metrics" &&
      (field.type === "FIELD_TYPE_JSON" || field.type === "FIELD_TYPE_STRING"),
  );
  let metrics: MetricItem[] = [];
  let error: string | undefined;
  try {
    if (result) metrics = statusMetrics(result.value);
    else if (metricField?.value) metrics = statusMetrics(JSON.parse(metricField.value));
  } catch (cause) {
    error =
      cause instanceof SyntaxError
        ? "Invalid metrics JSON."
        : cause instanceof Error
          ? cause.message
          : "Invalid metrics.";
  }
  return (
    <>
      {error && <p role="alert">Cannot display metrics: {error}</p>}
      {!!metrics.length && (
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
          {metrics.map((metric, i) => (
            <div key={`${metric.label}-${i}`} className="space-y-1 rounded-lg border p-3">
              <dt className="flex items-center gap-1.5 text-xs text-muted-foreground">
                {metric.status === "ok" && (
                  <CheckCircle aria-label="OK" className="size-3 text-green-500" />
                )}
                {metric.status && metric.status !== "ok" && (
                  <AlertCircle aria-label={metric.status} className="size-3" />
                )}
                {metric.label}
              </dt>
              <dd className="text-sm font-medium">{metric.value}</dd>
            </div>
          ))}
        </dl>
      )}
      {panel.fields
        .filter((f) => f !== metricField)
        .map((field) => (
          <FieldDisplay key={field.name} field={field} />
        ))}
    </>
  );
}

export function FormPanelRenderer({ panel }: PanelProps) {
  const writable = panel.fields.filter(
    (field) => field.editable !== false && field.configPath && field.type !== "FIELD_TYPE_MARKDOWN",
  );
  const fields = writable.map((field) => ({
    field,
    initialValue: field.value ?? "",
    // PatchNixData's config/_root branch requires the stackpanel. prefix.
    configPath: `stackpanel.${field.configPath}`,
  }));
  return (
    <>
      {fields.length > 0 && <EditableFieldGroup fields={fields} />}
      {panel.fields
        .filter((field) => !writable.includes(field))
        .map((field) => (
          <FieldDisplay key={field.name} field={field} />
        ))}
    </>
  );
}

export function TablePanelRenderer({ panel, result }: PanelProps & { result?: DataResult }) {
  let data;
  try {
    data = tableData(result ? result.value : (panel.rows ?? []), panel.columns ?? []);
  } catch (cause) {
    return (
      <p role="alert">
        Cannot display table: {cause instanceof Error ? cause.message : "Invalid data."}
      </p>
    );
  }
  const { rows, columns } = data;
  if (!rows.length) return <p className="text-sm text-muted-foreground">No data available</p>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm" aria-label={panel.title}>
        <thead>
          <tr className="border-b">
            {columns.map((col) => (
              <th key={col.key} scope="col" className="px-3 py-2 text-left">
                {col.label}
              </th>
            ))}
            {!!panel.rowActions?.length && (
              <th scope="col" className="px-3 py-2 text-left">
                Actions
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, idx) => (
            <tr key={typeof row.id === "string" ? row.id : idx} className="border-b last:border-0">
              {columns.map((col) => (
                <td key={col.key} className="px-3 py-2">
                  {displayCell(Object.hasOwn(row, col.key) ? row[col.key] : undefined)}
                </td>
              ))}
              {!!panel.rowActions?.length && (
                <td className="px-3 py-2">
                  <ActionButtons actionIds={panel.rowActions} row={row} />
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function AppsGridPanelRenderer({ panel }: PanelProps) {
  const apps = Object.entries(panel.apps);
  if (!apps.length) return <p className="text-sm text-muted-foreground">No apps configured</p>;
  return (
    <div className="space-y-2">
      {apps.map(([name, app]) => (
        <div key={name} className="flex flex-wrap items-center gap-3 rounded-md border px-3 py-2">
          <span className="font-medium">{name}</span>
          <Badge variant="secondary">{app.enabled ? "Enabled" : "Disabled"}</Badge>
          {Object.entries(app.config).map(([key, value]) => {
            const field = panel.fields.find((f) => f.name === key);
            return field ? (
              <FieldDisplay key={key} field={{ ...field, value }} />
            ) : (
              <Badge key={key} variant="outline">
                {key}: {value}
              </Badge>
            );
          })}
        </div>
      ))}
    </div>
  );
}

function AppConfigFields({ panel, appId }: { panel: NixPanel; appId: string }) {
  const patch = usePatchNixData();
  const app = panel.apps[appId];
  if (!app) return null;
  return (
    <FieldGroup className="max-w-md">
      {panel.fields.map((field) => (
        <FieldRenderer
          key={field.name}
          field={field}
          value={app.config[field.name] ?? field.value ?? ""}
          disabled={!field.editable || !field.editPath}
          isSaving={patch.isPending}
          onChange={(next) => {
            if (!field.editPath || !field.editable) return;
            const valueType =
              (
                {
                  FIELD_TYPE_BOOLEAN: "bool",
                  FIELD_TYPE_NUMBER: "number",
                  FIELD_TYPE_MULTISELECT: "list",
                  FIELD_TYPE_JSON: "object",
                } as Record<string, string>
              )[field.type] ?? "string";
            patch.mutate({
              entity: "apps",
              key: appId,
              path: field.editPath,
              valueType,
              value: valueType === "string" ? JSON.stringify(next) : next,
            });
          }}
        />
      ))}
      {patch.error && (
        <p role="alert" className="text-sm text-destructive">
          {patch.error.message}
        </p>
      )}
    </FieldGroup>
  );
}

function PanelTabs({ panel, panels, appId, ancestors }: PanelTreeProps) {
  const [selection, setSelection] = useState("");
  const byId = new Map(
    panels
      .filter(
        (candidate) =>
          candidate.enabled &&
          candidate.module === panel.module &&
          candidate.slot === panel.slot &&
          (!appId || studioPanelMatchesApp(candidate, appId)),
      )
      .map((candidate) => [candidate.id, candidate]),
  );
  const tabs = [...new Set(panel.tabs)].flatMap((id) => {
    const child = byId.get(id);
    return child && !ancestors.includes(id) && id !== panel.id ? [child] : [];
  });
  if (!tabs.length) return <p className="text-sm text-muted-foreground">No available tabs.</p>;
  const active = tabs.find((tab) => tab.id === selection) ?? tabs[0]!;
  return (
    <Tabs value={active.id} onValueChange={setSelection}>
      <TabsList aria-label={panel.title}>
        {tabs.map((tab) => (
          <TabsTrigger key={tab.id} value={tab.id}>
            {tab.title}
          </TabsTrigger>
        ))}
      </TabsList>
      <TabsContent key={active.id} value={active.id}>
        <PanelTree
          panel={active}
          panels={panels}
          appId={appId}
          ancestors={[...ancestors, panel.id]}
        />
      </TabsContent>
    </Tabs>
  );
}

function PanelBody(props: PanelTreeProps & { result?: DataResult }) {
  const { panel, appId } = props;
  switch (panel.type) {
    case "PANEL_TYPE_STATUS":
      return <StatusPanelRenderer {...props} />;
    case "PANEL_TYPE_TABLE":
      return <TablePanelRenderer {...props} />;
    case "PANEL_TYPE_FORM":
      return <FormPanelRenderer panel={panel} />;
    case "PANEL_TYPE_APPS_GRID":
      return <AppsGridPanelRenderer panel={panel} />;
    case "PANEL_TYPE_TABS":
      return <PanelTabs {...props} />;
    case "PANEL_TYPE_CUSTOM":
      return <SandboxedCustomPanel panel={panel} appId={appId} />;
    case "PANEL_TYPE_APP_CONFIG": {
      const apps = Object.entries(panel.apps).filter(
        ([name, app]) => app.enabled === true && (!appId || name === appId),
      );
      if (!apps.length)
        return <p className="text-sm text-muted-foreground">No apps have this module enabled.</p>;
      return apps.map(([name]) => (
        <section key={name} className="space-y-2">
          <h4 className="text-sm font-medium">{name}</h4>
          <AppConfigFields panel={panel} appId={name} />
        </section>
      ));
    }
    case "PANEL_TYPE_UNSPECIFIED":
      return panel.fields.map((field) => <FieldDisplay key={field.name} field={field} />);
    default:
      return <p role="alert">Unsupported panel type: {panel.type}</p>;
  }
}

function PanelTree(props: PanelTreeProps) {
  const { panel } = props;
  const [result, setResult] = useState<DataResult>();
  const Icon = panel.icon && getModuleIconByName(panel.icon);
  const hasSpec = panel.type === "PANEL_TYPE_SPEC" || panel.spec != null;
  const dataAction =
    panel.type === "PANEL_TYPE_TABLE" || panel.type === "PANEL_TYPE_STATUS"
      ? panel.dataAction
      : null;
  const interactive =
    !hasSpec && !!(dataAction || panel.actions?.length || panel.rowActions?.length);
  const card = (
    <Card>
      <CardHeader className="space-y-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          {Icon && <Icon aria-hidden="true" className="size-4" />}
          {panel.title}
        </CardTitle>
        {panel.description && <CardDescription>{panel.description}</CardDescription>}
        {interactive && (
          <ActionButtons
            actionIds={panel.actions ?? []}
            dataAction={dataAction}
            onData={(value) => setResult({ value })}
          />
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        {panel.readme && <ModuleMarkdown>{panel.readme}</ModuleMarkdown>}
        {hasSpec ? (
          panel.type !== "PANEL_TYPE_SPEC" || panel.uiBundle ? (
            <p role="alert">A panel spec cannot be combined with another renderer.</p>
          ) : (
            <SpecPanel
              document={panel.spec}
              moduleId={panel.module}
              panelId={panel.id}
              title={panel.title}
              appId={props.appId}
            />
          )
        ) : (
          <PanelBody {...props} result={result} />
        )}
      </CardContent>
    </Card>
  );
  return interactive ? <PanelActionScope moduleId={panel.module}>{card}</PanelActionScope> : card;
}

export function PanelRenderer(props: CatalogPanelProps) {
  const { panel, appId } = props;
  const scope = useModuleQueryScope();
  return (
    <PanelTree
      key={JSON.stringify([...scope, panel.module, panel.id, panel.type, panel.dataAction, appId])}
      {...props}
      ancestors={[]}
    />
  );
}
