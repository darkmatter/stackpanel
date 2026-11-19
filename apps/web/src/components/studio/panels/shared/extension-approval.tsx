import { Button } from "@stackpanel/ui-web/button";
import { useCallback, useRef, useState } from "react";
import type { FrameOperations } from "./extension-policy";
import type { DocumentPreview } from "./extension-runtime";

interface PendingReview {
  readonly id: number;
  readonly message: string;
  decide(allow: boolean): void;
}

/** One live review, no queue and no remembered decisions. The operation's
 * signal is aborted on cancellation, timeout, revocation or frame unmount. */
export function useExtensionReview() {
  const [pending, setPending] = useState<PendingReview | null>(null);
  const current = useRef<PendingReview | null>(null);
  const nextId = useRef(0);
  const confirm = useCallback<FrameOperations["confirm"]>((message, signal) => {
    if (signal.aborted || current.current) return Promise.resolve(false);
    const { promise, resolve } = Promise.withResolvers<boolean>();
    const cancel = () => request.decide(false);
    const request: PendingReview = {
      id: ++nextId.current,
      message,
      decide(allow) {
        if (current.current !== request) return;
        current.current = null;
        signal.removeEventListener("abort", cancel);
        setPending(null);
        resolve(allow && !signal.aborted);
      },
    };
    current.current = request;
    signal.addEventListener("abort", cancel, { once: true });
    setPending(request);
    return promise;
  }, []);
  return { pending, confirm };
}

export function OperationReview({ request }: { request: PendingReview }) {
  return (
    <section
      aria-label="Studio request review"
      className="grid gap-2 rounded-md border bg-card p-3 text-sm"
    >
      <h3 className="font-semibold">Studio request review</h3>
      <p aria-live="polite" className="whitespace-pre-wrap break-all">
        {request.message}
      </p>
      <div className="flex gap-2">
        <Button type="button" size="sm" variant="outline" onClick={() => request.decide(false)}>
          Deny request
        </Button>
        <Button type="button" size="sm" onClick={() => request.decide(true)}>
          Allow once
        </Button>
      </div>
    </section>
  );
}

export function RefreshPanelReview({ reason }: { reason?: string }) {
  return (
    <div>
      <p role="alert">
        {reason ?? "Studio could not verify this panel against the project snapshot."} Refresh the
        project and review the panel again.
      </p>
      <Button type="button" size="sm" variant="outline" onClick={() => window.location.reload()}>
        Refresh project
      </Button>
    </div>
  );
}

export function DocumentReview({
  preview,
  open,
  deny,
}: {
  preview: DocumentPreview;
  open: () => void;
  deny: () => void;
}) {
  const { source, projectId, context } = preview;
  const development = source.kind === "dev";
  return (
    <section
      aria-label="Studio panel permissions"
      className="grid gap-2 rounded-md border bg-card p-3 text-sm"
    >
      <p role="status">
        Opening asks the agent to prepare the panel, which may download its bundle.
      </p>
      <h3 className="font-semibold">
        {development ? "Locally linked development server" : "Production bundle"}
      </h3>
      <p className="break-all">Origin: {source.origin}</p>
      <p>
        Project: {projectId} · Module: {context.moduleId} · Panel: {context.panelId} · App:{" "}
        {context.appId ?? "(none)"}
      </p>
      <p>
        {development
          ? "Open only if you trust this local server and its code. It supplies its own content security policy (CSP); scripts and hot updates can contact the network directly. Studio cannot review that traffic."
          : "Opening runs module code in a sandboxed document with the agent’s content security policy. Only open panels from modules you trust."}
      </p>
      <p>Panel capabilities: {context.permissions.join(", ") || "none"}.</p>
      {context.permissions.includes("config:read") && <p>The panel can read its settings.</p>}
      {context.permissions.includes("config:patch") && (
        <p>The panel can change its settings without asking again.</p>
      )}
      <p>
        Studio asks before each service request or executable action sent through the bridge.
        Opening applies to this document only. Stop the panel to close it and revoke access.
      </p>
      <div className="flex gap-2">
        <Button type="button" size="sm" variant="outline" onClick={deny}>
          Deny
        </Button>
        <Button type="button" size="sm" onClick={open}>
          Open panel once
        </Button>
      </div>
    </section>
  );
}
