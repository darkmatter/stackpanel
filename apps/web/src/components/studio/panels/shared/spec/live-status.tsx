"use client";

import { equals, fromJson } from "@bufbuild/protobuf";
import type { Client } from "@connectrpc/connect";
import {
  registerPanelElements,
  type PanelCommandElement,
  type PanelElementRun,
} from "@stackpanel/extension-sdk/elements";
import type { JsonObject } from "@stackpanel/extension-sdk/protocol";
import {
  ModuleActionSchema,
  ModuleService,
  type ModuleAction,
  type OpenModuleUIRequest,
} from "@stackpanel/proto/agent/v1/module";
import { hashKey } from "@tanstack/react-query";
import { createElement, useLayoutEffect, useMemo, useRef, useState } from "react";
import { useModuleServiceClient } from "@/lib/agent-provider";
import { useModuleQueryScope } from "../../modules/use-modules";
import { collectExtensionAction } from "../extension-action-stream";
import { grantHeader, isReviewRevision, openReviewedUI } from "../extension-runtime";
import { hasActionReview, isJsonObject } from "../panel-data";
import { studioPanelMatchesApp, useStudioPanels } from "../use-studio-panels";
import { isPanelTargetId } from "./author-schema";

interface Props {
  moduleId: string;
  panelId: string;
  appId?: string;
  action: string;
  app?: string;
  allowedApps: readonly string[];
}

type ModuleClient = Client<typeof ModuleService>;
interface StatusGrant {
  token: string;
  expiresAt: number;
  apps: readonly string[];
}
const authorizeAgain =
  "Status authorization is unavailable or has changed. Review the target and approve again.";

// Use the snapshot that rendered the panel. Do not fetch module data on mount or
// silently substitute metadata from a newer evaluation for the one being approved.
function actionSnapshot(config: Record<string, unknown> | null, moduleId: string, action: string) {
  const modules: unknown = config?.modulesListAll;
  if (!Array.isArray(modules)) return;
  const mod: unknown = modules.find((v: unknown) => isJsonObject(v) && v.id === moduleId);
  if (!isJsonObject(mod) || mod.enabled !== true || !isJsonObject(mod.actions)) return;
  if (!Object.hasOwn(mod.actions, action)) return;
  const raw = mod.actions[action];
  if (!hasActionReview(raw) || raw.confirm != null) return;
  try {
    return {
      descriptor: fromJson(ModuleActionSchema, raw, { ignoreUnknownFields: true }),
      // Includes evaluated executable metadata when supplied. It only narrows
      // the lifetime of this mount; Studio never sends an executable to run.
      revision: hashKey([raw]),
    };
  } catch {
    return;
  }
}

async function openStatusGrant(
  client: ModuleClient,
  request: Pick<
    OpenModuleUIRequest,
    "moduleId" | "panelId" | "appId" | "reviewRevision" | "statusAction" | "statusApps"
  >,
  reviewed: ModuleAction,
  signal: AbortSignal,
): Promise<StatusGrant> {
  const { opened, grant, expiresAt } = await openReviewedUI(client, request, signal);
  const grantOnly =
    opened.url === "" &&
    opened.devUrl === "" &&
    opened.settings === undefined &&
    opened.permissions.length === 1 &&
    opened.permissions[0] === "actions:run";
  const action = request.statusAction;
  const singleAction =
    opened.actionIds.length === 1 &&
    opened.actionIds[0] === action &&
    Object.keys(opened.actions).length === 1 &&
    Object.hasOwn(opened.actions, action);
  const granted = singleAction ? opened.actions[action] : undefined;
  if (
    !grantOnly ||
    !granted ||
    granted.confirm !== undefined ||
    !equals(ModuleActionSchema, reviewed, granted)
  ) {
    throw new Error(authorizeAgain);
  }
  return { token: grant, expiresAt, apps: request.statusApps };
}

// Narrow the ordinary app field constraints for the operator's review. The
// agent validates every requested target against the full schema before Open.
function acceptsTarget(schema: JsonObject, app: string | undefined) {
  if (
    schema.required !== undefined &&
    (!Array.isArray(schema.required) || schema.required.some((key) => key !== "app" || !app))
  )
    return false;
  if (schema.properties !== undefined && !isJsonObject(schema.properties)) return false;
  if (app === undefined) return true;
  if (!isPanelTargetId(app)) return false;
  const field = isJsonObject(schema.properties) ? schema.properties.app : undefined;
  if (field === undefined) return schema.additionalProperties !== false;
  if (!isJsonObject(field)) return field === true;
  return (
    (field.type === undefined || field.type === "string") &&
    (field.const === undefined || field.const === app) &&
    (field.enum === undefined || (Array.isArray(field.enum) && field.enum.includes(app)))
  );
}

export function LiveStatus({ moduleId, panelId, appId, action, app, allowedApps }: Props) {
  const scope = useModuleQueryScope();
  const projectId = scope[4];
  const client = useModuleServiceClient();
  const { config, catalog, error, isLoading } = useStudioPanels();
  const panel = catalog.find((p) => p.module === moduleId && p.id === panelId);
  const snapshot = useMemo(
    () => actionSnapshot(config, moduleId, action),
    [config, moduleId, action],
  );
  const documentKey = useMemo(() => hashKey([panel?.spec]), [panel?.spec]);
  const reviewRevision = panel?.uiReview?.revision;
  if (!client || !scope[6] || !projectId?.trim()) {
    return <p role="status">Pair an agent and select a project to load status.</p>;
  }
  if (error) return <p role="alert">Could not load the status review: {error.message}</p>;
  if (
    isLoading ||
    panel?.enabled !== true ||
    panel.type !== "PANEL_TYPE_SPEC" ||
    panel.uiBundle ||
    !snapshot
  ) {
    return (
      <p role="status">
        Live status is unavailable for {moduleId} / {panelId} / {action}.
      </p>
    );
  }
  if (!isReviewRevision(reviewRevision)) {
    return (
      <p role="status">
        This status action has no valid review revision. Refresh the project and review it again.
      </p>
    );
  }
  const invalidMount =
    panel.slot.startsWith("app:") !== (appId !== undefined) ||
    (appId !== undefined &&
      (!isPanelTargetId(appId) || !studioPanelMatchesApp(panel, appId) || app !== appId));
  const schema = snapshot.descriptor.argsSchema!;
  const reviewedApps = allowedApps.filter(
    (name) => (appId === undefined || name === appId) && acceptsTarget(schema, name),
  );
  const validSelection =
    app === undefined
      ? allowedApps.length === 0 && acceptsTarget(schema, undefined)
      : reviewedApps.includes(app);
  if (invalidMount || !validSelection) {
    return (
      <p role="status">
        Select a valid target for {action}
        {appId ? ` in app ${appId}` : ""}.
      </p>
    );
  }
  return (
    <BoundStatus
      key={`${hashKey([...scope, moduleId, panelId, appId, action, panel.slot, reviewRevision, reviewedApps])}:${snapshot.revision}:${documentKey}`}
      client={client}
      projectId={projectId}
      moduleId={moduleId}
      panelId={panelId}
      appId={appId}
      action={action}
      app={app}
      reviewRevision={reviewRevision}
      allowedApps={reviewedApps}
      descriptor={snapshot.descriptor}
    />
  );
}

interface BoundProps extends Props {
  client: ModuleClient;
  projectId: string;
  reviewRevision: string;
  descriptor: ModuleAction;
}

function BoundStatus({
  client,
  projectId,
  moduleId,
  panelId,
  appId,
  action,
  app,
  descriptor,
  reviewRevision,
  allowedApps,
}: BoundProps) {
  const node = useRef<PanelCommandElement>(null);
  const currentApp = useRef(app);
  // The parent keys this instance by descriptor *value*. An equivalent query
  // snapshot must not stop an authorized stream just because JSON was reparsed.
  const [reviewed] = useState(() => ({ descriptor, apps: allowedApps }));
  const [expired, setExpired] = useState(false);
  useLayoutEffect(() => {
    registerPanelElements();
    const view = node.current;
    if (!view) return;
    const mount = new AbortController();
    let automatic: StatusGrant | undefined;
    let expiryTimer: number | undefined;
    let active: AbortController | undefined;
    function revoke() {
      window.clearTimeout(expiryTimer);
      automatic = undefined;
      active?.abort();
    }
    const run: PanelElementRun = async (id, args, request, reason) => {
      mount.signal.throwIfAborted();
      request.throwIfAborted();
      const target = currentApp.current;
      if (
        !view.isConnected ||
        view.run !== run ||
        id !== action ||
        Object.keys(args).length !== Number(target !== undefined) ||
        (target !== undefined && args.app !== target)
      )
        throw new Error(authorizeAgain);
      // A selection change can consume, but never acquire, a grant. In
      // particular, a failed or cancelled first approval cannot be retried by
      // the next prop update, even before the element processes the rejection.
      const manual = reason === "load-once" || reason === "allow-automatic";
      if (!manual && reason !== "selection-change") throw new Error(authorizeAgain);
      if (manual) revoke();
      const operation = new AbortController();
      active = operation;
      const signal = AbortSignal.any([mount.signal, request, operation.signal]);
      try {
        if (
          reason === "allow-automatic" &&
          (target === undefined || !reviewed.apps.includes(target))
        ) {
          throw new Error(authorizeAgain);
        }
        let grant = automatic;
        if (manual) {
          const statusApps = reason === "allow-automatic" ? [...reviewed.apps] : [];
          if (reason === "load-once" && target !== undefined) statusApps.push(target);
          grant = await openStatusGrant(
            client,
            {
              moduleId,
              panelId,
              appId: appId ?? "",
              reviewRevision,
              statusAction: action,
              statusApps,
            },
            reviewed.descriptor,
            signal,
          );
        }
        signal.throwIfAborted();
        if (
          !grant ||
          currentApp.current !== target ||
          Date.now() >= grant.expiresAt ||
          (target === undefined ? grant.apps.length !== 0 : !grant.apps.includes(target))
        ) {
          throw new Error(authorizeAgain);
        }
        if (manual) {
          setExpired(false);
          expiryTimer = window.setTimeout(() => {
            revoke();
            // Reset opt-in, pending work and old output in the actual SDK view.
            view.run = null;
            view.run = run;
            setExpired(true);
          }, grant.expiresAt - Date.now());
        }
        const boundArgs: JsonObject = target === undefined ? {} : { app: target };
        const result = await collectExtensionAction(signal, (streamSignal) =>
          client.runModuleAction(
            { moduleId, actionId: action, args: boundArgs },
            { headers: { [grantHeader]: grant.token }, signal: streamSignal },
          ),
        );
        signal.throwIfAborted();
        if (Date.now() >= grant.expiresAt) throw new Error(authorizeAgain);
        if (reason === "allow-automatic" && result.exitCode === 0) automatic = grant;
        return result;
      } catch (error) {
        // A superseded selection's late rejection must not revoke the new run.
        if (active === operation && !signal.aborted) revoke();
        if (error instanceof Error && error.message !== authorizeAgain)
          throw new Error(`${error.message} ${authorizeAgain}`, { cause: error });
        throw error;
      } finally {
        if (active === operation) {
          active = undefined;
          if (!automatic) window.clearTimeout(expiryTimer);
        }
      }
    };
    view.addEventListener("sp-updates-stopped", revoke);
    view.run = run;
    view.action = action;
    return () => {
      mount.abort();
      revoke();
      view.removeEventListener("sp-updates-stopped", revoke);
      view.run = null;
    };
  }, [client, moduleId, panelId, appId, action, reviewed, reviewRevision]);
  useLayoutEffect(() => {
    currentApp.current = app;
    if (node.current) node.current.args = app === undefined ? {} : { app };
  }, [app]);
  return (
    <section aria-label="Live status authorization" className="space-y-2">
      <p className="text-sm">
        Project: <strong>{projectId}</strong> · Module: {moduleId} · Panel: {panelId} · Action:{" "}
        <strong>{action}</strong> · Target: {app ?? "(no app)"}
      </p>
      <p className="text-sm text-muted-foreground">
        This native module action runs on the agent and can contact the network. Load once approves
        this target only.
        {app !== undefined && (
          <>
            {" "}
            Automatic updates approve selection changes only among these apps while this panel is
            open: {reviewed.apps.join(", ")}.
          </>
        )}
      </p>
      {expired && <p role="status">Authorization expired. Review the target and approve again.</p>}
      {createElement("sp-status-view", { ref: node })}
    </section>
  );
}
