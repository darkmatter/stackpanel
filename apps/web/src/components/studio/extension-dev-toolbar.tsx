"use client";

import { Button } from "@stackpanel/ui-web/button";
import { useQueryClient } from "@tanstack/react-query";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { z } from "zod";
import { useAgentContext } from "@/lib/agent-provider";
import { useAgentSSEOptional } from "@/lib/agent-sse-provider";
import { useModuleCatalog, useModuleQueryScope } from "./panels/modules/use-modules";
import { localDevUrl } from "./panels/shared/extension-url";
import type { PermissionLog } from "./panels/shared/extension-session";

const diagnosticsSchema = z.object({
  projectId: z.string(),
  linkedModules: z.record(z.string(), z.object({ uiDevUrl: z.string().optional() })),
  durationMs: z.number().nonnegative().optional(),
  error: z.string().optional(),
});
type Diagnostics = z.infer<typeof diagnosticsSchema>;
type Audit = PermissionLog & { moduleId: string; panelId: string };
interface DevTools {
  revision: ReadonlyMap<string, number>;
  links: ReadonlyMap<string, string>;
  audit: (entry: Audit) => void;
}
const DevContext = createContext<DevTools | null>(null);
export const useExtensionDevTools = () => useContext(DevContext);

/** Keep diagnostics, log history, and reload generations scoped to this tab's project. */
export function ExtensionDevToolsProvider({ children }: { children: ReactNode }) {
  const { host, port, selectedProjectId, isAuthenticated } = useAgentContext();
  const id = isAuthenticated ? selectedProjectId : null;
  return (
    <ProjectDevTools key={JSON.stringify([host, port, id])} projectId={id}>
      {children}
    </ProjectDevTools>
  );
}

function ProjectDevTools({
  projectId,
  children,
}: {
  projectId: string | null;
  children: ReactNode;
}) {
  const catalog = useModuleCatalog(Boolean(projectId));
  const scope = useModuleQueryScope();
  const cache = useQueryClient();
  const subscribe = useAgentSSEOptional()?.addEventListener;
  const [diagnostics, setDiagnostics] = useState<Diagnostics | null>(null);
  const [logs, setLogs] = useState<Audit[]>([]);
  const [revision, setRevision] = useState(new Map<string, number>());
  const [selected, setSelected] = useState("");
  const [reloadError, setReloadError] = useState("");
  const [reloading, setReloading] = useState(false);
  useEffect(
    () =>
      subscribe?.("module.dev.diagnostics", ({ data }) => {
        const info = diagnosticsSchema.safeParse(data);
        if (projectId && info.success && info.data.projectId === projectId)
          setDiagnostics(info.data);
      }),
    [projectId, subscribe],
  );
  const links = useMemo(() => {
    if (diagnostics)
      return new Map(
        Object.entries(diagnostics.linkedModules).map(([id, link]) => [id, link.uiDevUrl ?? ""]),
      );
    return new Map(
      catalog.data?.modules.filter((mod) => mod.linked).map((mod) => [mod.id, mod.uiDevUrl ?? ""]),
    );
  }, [catalog.data, diagnostics]);
  const active = links.has(selected) ? selected : links.keys().next().value;
  const audit = useCallback(
    (entry: Audit) => {
      if (links.has(entry.moduleId)) setLogs((prev) => [...prev.slice(-63), entry]);
    },
    [links],
  );
  const context = useMemo(() => ({ revision, links, audit }), [revision, links, audit]);
  async function reload() {
    if (!projectId || !active || reloading) return;
    setReloading(true);
    setReloadError("");
    // A fresh frame means a fresh server-issued launch grant, even with Vite HMR.
    setRevision((old) => new Map(old).set(active, (old.get(active) ?? 0) + 1));
    try {
      await cache.invalidateQueries({ queryKey: scope }, { throwOnError: true });
    } catch (error) {
      setReloadError(error instanceof Error ? error.message : "Module reload failed");
    } finally {
      setReloading(false);
    }
  }
  return (
    <DevContext.Provider value={context}>
      {children}
      {projectId && active && (
        <aside
          aria-label="Extension development"
          className="fixed right-4 bottom-4 z-40 max-w-md rounded-md border bg-card p-3 text-card-foreground shadow-md"
        >
          <details>
            <summary className="cursor-pointer text-sm font-semibold">
              Extension development · {active}
            </summary>
            <div className="mt-2 grid gap-2 text-xs">
              <label>
                Linked module{" "}
                <select value={active} onChange={(e) => setSelected(e.target.value)}>
                  {[...links.keys()].map((id) => (
                    <option key={id} value={id}>
                      {id}
                    </option>
                  ))}
                </select>
              </label>
              <span>
                HMR:{" "}
                {links.get(active)
                  ? (localDevUrl(links.get(active)!)?.origin ?? "Invalid loopback server")
                  : "Static bundle"}
              </span>
              <span>
                Nix evaluation:{" "}
                {diagnostics?.durationMs === undefined
                  ? "No timing reported"
                  : `${diagnostics.durationMs} ms`}
              </span>
              {(diagnostics?.error || reloadError) && (
                <pre
                  role="alert"
                  className="max-h-40 overflow-auto whitespace-pre-wrap text-destructive"
                >
                  {reloadError || diagnostics?.error}
                </pre>
              )}
              <details>
                <summary className="cursor-pointer">SDK permission log</summary>
                <ol aria-label="SDK permission log" className="max-h-32 overflow-y-auto font-mono">
                  {logs
                    .filter((entry) => entry.moduleId === active)
                    .map((entry, index) => (
                      <li key={`${entry.panelId}:${entry.id}:${index}`}>
                        {entry.panelId}: {entry.method} — {entry.outcome}
                      </li>
                    ))}
                </ol>
              </details>
              <Button disabled={reloading} size="sm" variant="outline" onClick={reload}>
                {reloading ? "Reloading…" : "Reload Module"}
              </Button>
            </div>
          </details>
        </aside>
      )}
    </DevContext.Provider>
  );
}
