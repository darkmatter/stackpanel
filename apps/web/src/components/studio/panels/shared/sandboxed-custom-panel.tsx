"use client";

import { Button } from "@stackpanel/ui-web/button";
import { useCallback, useLayoutEffect, useMemo, useRef, useState } from "react";
import { canonicalAgentOrigin } from "@/lib/agent-identity";
import { useAgentContext, useModuleServiceClient } from "@/lib/agent-provider";
import { useAgentSSEOptional } from "@/lib/agent-sse-provider";
import { useExtensionDevTools } from "../../extension-dev-toolbar";
import {
  DocumentReview,
  OperationReview,
  RefreshPanelReview,
  useExtensionReview,
} from "./extension-approval";
import {
  isPanelPermissions,
  isReviewRevision,
  openExtension,
  type DocumentPreview,
  type ExtensionTarget,
  type OpenExtension,
} from "./extension-runtime";
import { bindExtensionFrame, type ExtensionFrameSession } from "./extension-session";
import { localDevUrl } from "./extension-url";
import type { NixPanel } from "./panel-types";
import { isJsonObject } from "./panel-data";
import { studioPanelMatchesApp } from "./use-studio-panels";

type Props = { panel: NixPanel; appId?: string };

export function SandboxedCustomPanel({ panel, appId }: Props) {
  const client = useModuleServiceClient();
  const { host, port, token, selectedProjectId, isAuthenticated } = useAgentContext();
  const dev = useExtensionDevTools();
  const reviewRevision = panel.uiReview?.revision;
  const target = useMemo<ExtensionTarget | null>(() => {
    if (!client || !token || !selectedProjectId || !isAuthenticated || !reviewRevision) return null;
    return {
      client,
      projectId: selectedProjectId,
      reviewRevision,
      agentOrigin: canonicalAgentOrigin(host, port),
      token,
      moduleId: panel.module,
      panelId: panel.id,
      appId,
    };
  }, [
    client,
    host,
    port,
    token,
    selectedProjectId,
    reviewRevision,
    isAuthenticated,
    panel.module,
    panel.id,
    appId,
  ]);
  if (panel.enabled !== true || panel.type !== "PANEL_TYPE_CUSTOM" || !panel.uiBundle) {
    return <p role="status">This extension panel is unavailable.</p>;
  }
  if (
    typeof panel.slot !== "string" ||
    !panel.slot ||
    !panel.module ||
    !panel.id ||
    !isJsonObject(panel.apps) ||
    typeof panel.uiBundle.package !== "string" ||
    !panel.uiBundle.package ||
    typeof panel.uiBundle.entry !== "string" ||
    !panel.uiBundle.entry
  )
    return <RefreshPanelReview />;
  const appSlot = panel.slot.startsWith("app:");
  if (
    appSlot !== (appId !== undefined) ||
    (appId !== undefined && (!appId.trim() || !studioPanelMatchesApp(panel, appId)))
  ) {
    return <p role="status">This extension is unavailable for the selected app.</p>;
  }
  if (!isReviewRevision(reviewRevision) || !isPanelPermissions(panel.uiBundle.permissions))
    return <RefreshPanelReview />;
  if (!target)
    return <p role="status">Pair an agent and select a project to open this extension.</p>;
  // These props can narrow/invalidate a document binding but cannot grant it
  // anything. Only project-scoped OpenModuleUI supplies the URL and grants.
  const devOrigin = panel.uiReview?.devOrigin;
  if (
    devOrigin !== undefined &&
    (typeof devOrigin !== "string" || localDevUrl(devOrigin)?.origin !== devOrigin)
  ) {
    return <RefreshPanelReview />;
  }
  const preview: DocumentPreview = {
    source: devOrigin
      ? { kind: "dev", origin: devOrigin }
      : { kind: "bundle", origin: target.agentOrigin },
    projectId: target.projectId,
    context: {
      moduleId: panel.module,
      panelId: panel.id,
      appId,
      permissions: [...panel.uiBundle.permissions],
    },
  };
  const key = JSON.stringify([
    target.projectId,
    panel.module,
    panel.id,
    appId,
    panel.uiBundle,
    dev?.revision.get(panel.module),
    reviewRevision,
    devOrigin,
  ]);
  return <LaunchPanel key={key} target={target} preview={preview} title={panel.title} />;
}

type LaunchState = { owner: ExtensionTarget } & (
  | { phase: "preparing" }
  | { phase: "failed"; reason: string }
  | { phase: "open"; opened: OpenExtension }
  | { phase: "closed"; message: string }
);
function LaunchPanel({
  target,
  preview,
  title,
}: {
  target: ExtensionTarget;
  preview: DocumentPreview;
  title: string;
}) {
  const [state, setState] = useState<LaunchState>();
  const preparing = useRef<AbortController | null>(null);
  useLayoutEffect(
    () => () => {
      preparing.current?.abort();
      preparing.current = null;
    },
    [target],
  );
  const revoke = useCallback(() => {
    preparing.current?.abort();
    preparing.current = null;
    setState({
      owner: target,
      phase: "closed",
      message: "Panel closed. Review it again to open a new document.",
    });
  }, [target]);
  async function prepare() {
    if (preparing.current) return;
    const controller = new AbortController();
    preparing.current = controller;
    setState({ phase: "preparing", owner: target });
    try {
      const opened = await openExtension(target, preview, controller.signal);
      if (controller.signal.aborted) return;
      if (Date.now() >= opened.authority.expiresAt) {
        revoke();
        return;
      }
      setState({ phase: "open", opened, owner: target });
    } catch (error) {
      if (!controller.signal.aborted) {
        setState({
          owner: target,
          phase: "failed",
          reason: error instanceof Error ? error.message : "Panel preparation failed.",
        });
      }
    } finally {
      if (preparing.current === controller) preparing.current = null;
    }
  }
  // A projected review is inert. Preparation can realize/download code, so
  // start it only from the host button, never on render, mount or retry.
  if (!state || state.owner !== target) {
    return <DocumentReview preview={preview} deny={revoke} open={() => void prepare()} />;
  }
  if (state.phase === "preparing") {
    return (
      <div>
        <p role="status">Preparing panel…</p>
        <Button type="button" size="sm" variant="outline" onClick={revoke}>
          Cancel opening
        </Button>
      </div>
    );
  }
  if (state.phase === "failed") return <RefreshPanelReview reason={state.reason} />;
  if (state.phase === "open") {
    return (
      <ExtensionFrame
        key={state.opened.nonce}
        opened={state.opened}
        title={title}
        revoke={revoke}
      />
    );
  }
  return (
    <div>
      <p role="status">{state.message}</p>
      <Button type="button" size="sm" variant="outline" onClick={() => setState(undefined)}>
        Review panel
      </Button>
    </div>
  );
}

function ExtensionFrame({
  opened,
  title,
  revoke,
}: {
  opened: OpenExtension;
  title: string;
  revoke: () => void;
}) {
  const ref = useRef<HTMLIFrameElement>(null);
  const sessionRef = useRef<ExtensionFrameSession | null>(null);
  const { pending, confirm } = useExtensionReview();
  const dev = useExtensionDevTools();
  const audit = useRef(dev?.audit);
  useLayoutEffect(() => {
    audit.current = dev?.audit;
  }, [dev?.audit]);
  const subscribe = useAgentSSEOptional()?.addEventListener;
  useLayoutEffect(() => {
    const frame = ref.current;
    if (!frame) return;
    const { moduleId, panelId } = opened.authority.context;
    const session = bindExtensionFrame(
      frame,
      opened.nonce,
      opened.authority,
      { ...opened.ops, confirm },
      (event) => audit.current?.({ ...event, moduleId, panelId }),
      revoke,
    );
    sessionRef.current = session;
    const expiry = window.setTimeout(
      () => {
        session.dispose();
        revoke();
      },
      Math.max(0, opened.authority.expiresAt - Date.now()),
    );
    return () => {
      window.clearTimeout(expiry);
      session.dispose();
      sessionRef.current = null;
    };
  }, [opened, confirm, revoke]);
  useLayoutEffect(() => {
    const session = sessionRef.current;
    if (!session) return;
    return subscribe?.("flake.config.updated", ({ data }) => {
      if (
        typeof data === "object" &&
        data !== null &&
        "projectId" in data &&
        data.projectId === opened.authority.projectId
      ) {
        void session.publishConfig().catch(revoke);
      }
    });
  }, [opened, revoke, subscribe]);
  return (
    <div className="grid gap-2">
      <div className="flex items-center justify-between gap-2 text-sm">
        <span>
          Studio ·{" "}
          {opened.source.kind === "dev" ? "Locally linked development server" : "Production bundle"}{" "}
          · {opened.source.origin}
        </span>
        <Button
          type="button"
          size="sm"
          variant="outline"
          onClick={() => {
            sessionRef.current?.dispose();
            revoke();
          }}
        >
          Stop panel
        </Button>
      </div>
      {pending && <OperationReview key={pending.id} request={pending} />}
      <iframe
        ref={ref}
        title={title}
        className="min-h-80 w-full rounded-md border bg-background"
        sandbox="allow-scripts"
        referrerPolicy="no-referrer"
        {...{ credentialless: "" }}
        src={opened.url}
      />
    </div>
  );
}
