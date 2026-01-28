"use client";

import { Button } from "@ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@ui/dialog";
import { Badge } from "@ui/badge";
import {
  ArrowDown,
  Copy,
  Download,
  Loader2,
  Pause,
  Play,
  RefreshCw,
  Terminal,
  Trash2,
} from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useProcessLogs } from "@/lib/use-agent";
import { useAgentClient } from "@/lib/agent-provider";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import type { LogMessage } from "@/lib/agent";

interface ProcessLogsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  processName: string;
  processStatus?: string;
  isRunning?: boolean;
}

/**
 * Dialog for viewing process logs with real-time streaming support.
 */
export function ProcessLogsDialog({
  open,
  onOpenChange,
  processName,
  processStatus,
  isRunning,
}: ProcessLogsDialogProps) {
  const client = useAgentClient();
  const logsContainerRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);
  const [isStreaming, setIsStreaming] = useState(false);
  const [streamedLogs, setStreamedLogs] = useState<string[]>([]);
  const wsRef = useRef<WebSocket | null>(null);

  // Fetch initial logs
  const { data: logsData, isLoading, refetch } = useProcessLogs(processName, {
    offset: 0,
    limit: 500,
    enabled: open,
  });

  // Combine fetched logs with streamed logs
  const allLogs = [...(logsData?.logs ?? []), ...streamedLogs];

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (autoScroll && logsContainerRef.current) {
      logsContainerRef.current.scrollTop = logsContainerRef.current.scrollHeight;
    }
  }, [allLogs.length, autoScroll]);

  // Handle scroll to detect if user scrolled up
  const handleScroll = useCallback(() => {
    if (!logsContainerRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = logsContainerRef.current;
    const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;
    setAutoScroll(isAtBottom);
  }, []);

  // Start WebSocket streaming
  const startStreaming = useCallback(() => {
    if (!client || wsRef.current) return;

    try {
      const ws = client.createProcessLogsWebSocket(processName, {
        follow: true,
        offset: 0,
      });

      ws.onopen = () => {
        setIsStreaming(true);
        toast.success("Connected to log stream");
      };

      ws.onmessage = (event) => {
        try {
          const msg: LogMessage = JSON.parse(event.data);
          setStreamedLogs((prev) => [...prev, msg.message]);
        } catch {
          // Handle non-JSON messages
          setStreamedLogs((prev) => [...prev, event.data]);
        }
      };

      ws.onclose = () => {
        setIsStreaming(false);
        wsRef.current = null;
      };

      ws.onerror = () => {
        setIsStreaming(false);
        wsRef.current = null;
        toast.error("Failed to connect to log stream");
      };

      wsRef.current = ws;
    } catch {
      toast.error("Failed to start log streaming");
    }
  }, [client, processName]);

  // Stop WebSocket streaming
  const stopStreaming = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
      setIsStreaming(false);
    }
  }, []);

  // Cleanup on unmount or close
  useEffect(() => {
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, []);

  // Reset streamed logs when dialog opens
  useEffect(() => {
    if (open) {
      setStreamedLogs([]);
    } else {
      stopStreaming();
    }
  }, [open, stopStreaming]);

  // Copy logs to clipboard (not memoized - simple click handler)
  const copyLogs = () => {
    const text = allLogs.join("\n");
    navigator.clipboard.writeText(text);
    toast.success("Logs copied to clipboard");
  };

  // Download logs as file (not memoized - simple click handler)
  const downloadLogs = () => {
    const text = allLogs.join("\n");
    const blob = new Blob([text], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${processName}-logs.txt`;
    a.click();
    URL.revokeObjectURL(url);
    toast.success("Logs downloaded");
  };

  // Clear streamed logs
  const clearLogs = () => {
    setStreamedLogs([]);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Terminal className="h-5 w-5" />
            Logs: {processName}
            {processStatus && (
              <Badge
                variant="outline"
                className={cn(
                  "ml-2 text-xs",
                  isRunning && "border-emerald-500/30 text-emerald-500"
                )}
              >
                {processStatus}
              </Badge>
            )}
          </DialogTitle>
          <DialogDescription>
            View real-time logs for this process
          </DialogDescription>
        </DialogHeader>

        {/* Toolbar */}
        <div className="flex items-center justify-between gap-2 border-b pb-3">
          <div className="flex items-center gap-2">
            {isStreaming ? (
              <Button variant="outline" size="sm" onClick={stopStreaming}>
                <Pause className="mr-2 h-4 w-4" />
                Pause Stream
              </Button>
            ) : (
              <Button variant="outline" size="sm" onClick={startStreaming}>
                <Play className="mr-2 h-4 w-4" />
                Stream Live
              </Button>
            )}
            <Button variant="outline" size="sm" onClick={() => refetch()}>
              <RefreshCw className="mr-2 h-4 w-4" />
              Refresh
            </Button>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={clearLogs} title="Clear streamed logs">
              <Trash2 className="h-4 w-4" />
            </Button>
            <Button variant="ghost" size="sm" onClick={copyLogs} title="Copy logs">
              <Copy className="h-4 w-4" />
            </Button>
            <Button variant="ghost" size="sm" onClick={downloadLogs} title="Download logs">
              <Download className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Logs container */}
        <div
          ref={logsContainerRef}
          onScroll={handleScroll}
          className="flex-1 overflow-auto bg-black/90 rounded-lg p-4 font-mono text-xs text-green-400 min-h-[300px] max-h-[500px]"
        >
          {isLoading ? (
            <div className="flex items-center justify-center h-full">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : allLogs.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-muted-foreground">
              <Terminal className="h-8 w-8 mb-2" />
              <p>No logs available</p>
              {isRunning && (
                <Button
                  variant="outline"
                  size="sm"
                  className="mt-4"
                  onClick={startStreaming}
                >
                  <Play className="mr-2 h-4 w-4" />
                  Start Streaming
                </Button>
              )}
            </div>
          ) : (
            <pre className="whitespace-pre-wrap break-words">
              {allLogs.map((line, i) => (
                <div key={i} className="hover:bg-white/5 px-1 -mx-1">
                  {line}
                </div>
              ))}
            </pre>
          )}
        </div>

        {/* Auto-scroll indicator */}
        {!autoScroll && allLogs.length > 0 && (
          <div className="absolute bottom-20 right-8">
            <Button
              size="sm"
              variant="secondary"
              onClick={() => {
                setAutoScroll(true);
                if (logsContainerRef.current) {
                  logsContainerRef.current.scrollTop = logsContainerRef.current.scrollHeight;
                }
              }}
            >
              <ArrowDown className="mr-2 h-4 w-4" />
              Scroll to bottom
            </Button>
          </div>
        )}

        {/* Streaming indicator */}
        {isStreaming && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
              <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500" />
            </span>
            Streaming live logs...
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
