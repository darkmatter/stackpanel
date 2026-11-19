import { useEffect, useRef, useState } from "react";
import { useAgentSSEEvent } from "./agent-sse-provider";

/**
 * Hook specifically for shell status SSE events.
 * Automatically updates when shell becomes stale or is rebuilt.
 *
 * NOTE: This hook requires AgentSSEProvider to be mounted in the component tree.
 * It uses the shared SSE connection from the provider instead of creating its own.
 */
export function useShellStatusSSE(onStatusChange?: (stale: boolean) => void) {
  const [isStale, setIsStale] = useState(false);
  const [isRebuilding, setIsRebuilding] = useState(false);
  const [lastChangedFile, setLastChangedFile] = useState<string | null>(null);

  // Store callback in ref to avoid re-subscribing on every render
  const onStatusChangeRef = useRef(onStatusChange);
  useEffect(() => {
    onStatusChangeRef.current = onStatusChange;
  }, [onStatusChange]);

  // Uses the shared AgentSSEProvider connection instead of creating a new one
  useAgentSSEEvent("shell.stale", (data: { file?: string }) => {
    setIsStale(true);
    if (data.file) {
      setLastChangedFile(data.file);
    }
    onStatusChangeRef.current?.(true);
  });

  useAgentSSEEvent("shell.rebuilding", () => {
    setIsRebuilding(true);
  });

  useAgentSSEEvent("shell.rebuilt", () => {
    setIsStale(false);
    setIsRebuilding(false);
    setLastChangedFile(null);
    onStatusChangeRef.current?.(false);
  });

  return {
    isStale,
    isRebuilding,
    lastChangedFile,
  };
}
