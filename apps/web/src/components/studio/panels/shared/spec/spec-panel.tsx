"use client";

import {
  ActionProvider,
  defineRegistry,
  Renderer,
  StateProvider,
  useBoundProp,
  VisibilityProvider,
  type ComponentContext,
} from "@json-render/react";
import { registerPanelElements } from "@stackpanel/extension-sdk/elements";
import { Alert, AlertDescription, AlertTitle } from "@ui/alert";
import { Badge } from "@ui/badge";
import { createContext, createElement, useContext, useMemo, type ReactNode } from "react";
import { useModuleQueryScope } from "../../modules/use-modules";
import { PanelActionScope, ActionButtons } from "../panel-action-bar";
import { panelCatalog, parsePanelSpec } from "./catalog";
import { LiveStatus } from "./live-status";

registerPanelElements();

type Owner = { moduleId: string; panelId: string; appId?: string };
const OwnerContext = createContext<Owner | null>(null);

function AppPicker({ props, bindings }: ComponentContext<typeof panelCatalog, "AppPicker">) {
  const [value, select] = useBoundProp(props.value, bindings?.value);
  return createElement("sp-app-picker", {
    label: props.label ?? "App",
    ref(node: HTMLElementTagNameMap["sp-app-picker"] | null) {
      if (!node) return;
      node.apps = props.apps;
      node.value = value ?? "";
      function changed() {
        if (node && (node.value === "" || props.apps.includes(node.value))) select(node.value);
      }
      node.addEventListener("change", changed);
      return () => node.removeEventListener("change", changed);
    },
  });
}

function StatusView({ props }: ComponentContext<typeof panelCatalog, "StatusView">) {
  const owner = useContext(OwnerContext);
  if (!owner) throw new Error("StatusView requires its host panel scope.");
  return (
    <LiveStatus {...owner} action={props.action} app={props.app} allowedApps={props.allowedApps} />
  );
}

const { registry } = defineRegistry(panelCatalog, {
  components: {
    Stack: ({ props, children }) => (
      <div
        className={
          props.direction === "horizontal"
            ? "flex flex-wrap items-start gap-3"
            : "flex flex-col gap-3"
        }
      >
        {children}
      </div>
    ),
    Section: ({ props, children }) => (
      <section className="space-y-2" aria-label={props.title}>
        <h4 className="text-sm font-medium">{props.title}</h4>
        {children}
      </section>
    ),
    Text: ({ props }) => <p className="whitespace-pre-wrap break-words text-sm">{props.content}</p>,
    Badge: ({ props }) => <Badge variant="secondary">{props.text}</Badge>,
    Metric: ({ props }) =>
      createElement("sp-metric", {
        ref(node: HTMLElementTagNameMap["sp-metric"] | null) {
          if (!node) return;
          node.label = props.label;
          node.value = props.value;
        },
      }),
    Table: ({ props }) =>
      createElement("sp-data-table", {
        ref(node: HTMLElementTagNameMap["sp-data-table"] | null) {
          if (!node) return;
          node.columns = props.columns;
          node.rows = props.rows;
        },
      }),
    Actions: ({ props }) => <ActionButtons actionIds={props.ids} />,
    AppPicker,
    StatusView,
  },
});

function OwnerActions({ moduleId, children }: { moduleId: string; children: ReactNode }) {
  const scope = useModuleQueryScope();
  return (
    <PanelActionScope key={JSON.stringify(scope)} moduleId={moduleId}>
      {children}
    </PanelActionScope>
  );
}

export function SpecPanel({
  document,
  moduleId,
  panelId,
  title,
  appId,
}: Owner & { document: unknown; title: string }) {
  const result = useMemo(() => {
    const parsed = parsePanelSpec(document);
    if (!parsed.ok) return parsed;
    // Equivalent query payloads need not interrupt an in-flight read/confirmation.
    const key = JSON.stringify(parsed.spec);
    const buttons = Object.values(parsed.spec.elements).some(
      ({ type, props }) =>
        type === "Actions" && (!Array.isArray(props.ids) || props.ids.length > 0),
    );
    return { ...parsed, key, buttons };
  }, [document]);
  if (!result.ok) {
    return (
      <Alert variant="destructive">
        <AlertTitle>
          Cannot display {title} ({moduleId} / {panelId}
          {appId && ` / ${appId}`})
        </AlertTitle>
        <AlertDescription>Check the panel spec: {result.error}</AlertDescription>
      </Alert>
    );
  }
  const { spec } = result;
  const content = <Renderer registry={registry} spec={spec} />;
  return (
    <StateProvider
      key={`${JSON.stringify([moduleId, panelId, appId, title])}:${result.key}`}
      initialState={{
        data: spec.state?.data ?? {},
        local: spec.state?.local ?? {},
        module: { id: moduleId },
        panel: { title },
        app: { id: appId ?? "" },
      }}
    >
      <OwnerContext.Provider value={{ moduleId, panelId, appId }}>
        <VisibilityProvider>
          <ActionProvider>
            {result.buttons ? <OwnerActions moduleId={moduleId}>{content}</OwnerActions> : content}
          </ActionProvider>
        </VisibilityProvider>
      </OwnerContext.Provider>
    </StateProvider>
  );
}
