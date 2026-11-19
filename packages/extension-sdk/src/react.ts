import { useCallback, useEffect, useState } from "react";
import {
  getConfig,
  getContext,
  onConfigChange,
  patchModuleConfig,
  proxyFetch,
  runAction,
  type ExtensionContext,
  type JsonObject,
  type ProxyOptions,
} from "./bridge.js";

function asError(reason: unknown) {
  return reason instanceof Error ? reason : new Error("Studio extension call failed");
}

interface ContextState {
  context: ExtensionContext | null;
  loading: boolean;
  error: Error | null;
}

/** Fetch the immutable context of this panel mount, without reading its settings. */
export function useExtensionContext(): ContextState {
  const [state, setState] = useState<ContextState>({ context: null, loading: true, error: null });
  useEffect(() => {
    let mounted = true;
    async function load() {
      try {
        const context = await getContext();
        if (mounted) setState({ context, loading: false, error: null });
      } catch (reason) {
        if (mounted) setState({ context: null, loading: false, error: asError(reason) });
      }
    }
    void load();
    return () => {
      mounted = false;
    };
  }, []);
  return state;
}

interface ConfigState {
  settings: JsonObject | null;
  appId?: string;
  patchModuleConfig?: typeof patchModuleConfig;
  loading: boolean;
  error: Error | null;
}

function useScopedConfig(appOnly: boolean): ConfigState {
  const [state, setState] = useState<ConfigState>({ settings: null, loading: true, error: null });
  useEffect(() => {
    let mounted = true;
    let notified = false;
    let unsubscribe: (() => void) | undefined;
    async function load() {
      try {
        const { appId, permissions } = await getContext();
        if (!mounted) return;
        if (appOnly && appId === undefined) throw new Error("This panel is not mounted in an app");
        const patch = permissions.includes("config:patch") ? patchModuleConfig : undefined;
        if (!permissions.includes("config:read")) {
          setState({
            settings: null,
            appId,
            patchModuleConfig: patch,
            loading: false,
            error: null,
          });
          return;
        }
        const update = (settings: JsonObject) => {
          if (mounted)
            setState({ settings, appId, patchModuleConfig: patch, loading: false, error: null });
        };
        // Subscribe before taking the snapshot. A slow read must never replace
        // a newer pushed value, including in React Strict Mode's second mount.
        unsubscribe = onConfigChange((settings) => {
          notified = true;
          update(settings);
        });
        const settings = await getConfig();
        if (!notified) update(settings);
      } catch (reason) {
        if (mounted && !notified)
          setState({ settings: null, loading: false, error: asError(reason) });
      }
    }
    void load();
    return () => {
      mounted = false;
      unsubscribe?.();
    };
  }, [appOnly]);
  return state;
}

/** Settings for this mount. Read and patch are independent permissions. */
export function useModuleConfig(): ConfigState {
  return useScopedConfig(false);
}

/** Current app only. The writer is present only with config:patch; it accepts relative settings. */
export function useAppModuleConfig(): ConfigState {
  return useScopedConfig(true);
}

export function useModuleAction(action: string) {
  return useCallback(
    (args?: JsonObject, signal?: AbortSignal) => runAction(action, args, signal),
    [action],
  );
}

export function useServiceProxy(service: string) {
  return useCallback(
    (path: string, options?: ProxyOptions) => proxyFetch(service, path, options),
    [service],
  );
}
