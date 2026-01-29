"use client";

import React, { useState, useCallback, useRef, useEffect } from "react";
import { Button } from "@ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@ui/dialog";
import { Badge } from "@ui/badge";
import {
  Copy,
  Download,
  Pause,
  Play,
  Terminal,
  Trash2,
  Radio,
  Wifi,
  WifiOff,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { useAgentSSE, useAgentSSEEvent } from "@/lib/agent-sse-provider";

// =============================================================================
// Types
// =============================================================================

interface LogEntry {
  id: number;
  timestamp: Date;
  event: string;
  data: unknown;
}

// =============================================================================
// AgentConsoleDialog
// =============================================================================

export function AgentConsoleDialog() {
  const [open, setOpen] = useState(false);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [isPaused, setIsPaused] = useState(false);
  const [autoScroll, setAutoScroll] = useState(true);
  const [filter, setFilter] = useState<string>("");
  const outputRef = useRef<HTMLDivElement>(null);
  const logIdRef = useRef(0);

  const { status, isAlive, lastHeartbeat } = useAgentSSE();

  // Subscribe to all SSE events using wildcard
  useAgentSSEEvent<unknown>("*", (data, event) => {
    if (isPaused) return;
    
    const entry: LogEntry = {
      id: logIdRef.current++,
      timestamp: new Date(event.receivedAt),
      event: event.event,
      data,
    };
    
    setLogs((prev) => [...prev.slice(-500), entry]); // Keep last 500 entries
  });

  // Auto-scroll to bottom when logs change
  useEffect(() => {
    if (autoScroll && outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  // Handle scroll to detect manual scrolling
  const handleScroll = useCallback(() => {
    if (!outputRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = outputRef.current;
    const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;
    setAutoScroll(isAtBottom);
  }, []);

  // Clear logs
  const clearLogs = useCallback(() => {
    setLogs([]);
    logIdRef.current = 0;
    toast.success("Console cleared");
  }, []);

  // Copy logs to clipboard
  const copyLogs = useCallback(() => {
    const text = logs
      .map((log) => `[${log.timestamp.toISOString()}] ${log.event}: ${JSON.stringify(log.data)}`)
      .join("\n");
    navigator.clipboard.writeText(text);
    toast.success("Logs copied to clipboard");
  }, [logs]);

  // Download logs as JSON
  const downloadLogs = useCallback(() => {
    const data = JSON.stringify(logs, null, 2);
    const blob = new Blob([data], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `agent-console-${new Date().toISOString()}.json`;
    a.click();
    URL.revokeObjectURL(url);
    toast.success("Logs downloaded");
  }, [logs]);

  // Filter logs
  const filteredLogs = filter
    ? logs.filter((log) => 
        log.event.toLowerCase().includes(filter.toLowerCase()) ||
        JSON.stringify(log.data).toLowerCase().includes(filter.toLowerCase())
      )
    : logs;

  // Format timestamp
  const formatTime = (date: Date) => {
    return date.toLocaleTimeString("en-US", {
      hour12: false,
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      fractionalSecondDigits: 3,
    });
  };

  // Get event color
  const getEventColor = (event: string) => {
    if (event === "ping") return "text-muted-foreground/50";
    if (event === "connected") return "text-emerald-400";
    if (event === "error" || event.includes("error")) return "text-red-400";
    if (event === "config-changed" || event.includes("changed")) return "text-amber-400";
    if (event === "shell-status") return "text-blue-400";
    return "text-cyan-400";
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="text-muted-foreground hover:text-foreground relative"
        >
          <Terminal className="h-5 w-5" />
          {isAlive && (
            <span className="absolute top-1 right-1 h-2 w-2 rounded-full bg-emerald-500 animate-pulse" />
          )}
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-4xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Terminal className="h-5 w-5" />
            Agent Console
            <Badge 
              variant="outline" 
              className={cn(
                "ml-2 text-xs",
                isAlive 
                  ? "border-emerald-500/30 text-emerald-500" 
                  : status === "connecting"
                    ? "border-amber-500/30 text-amber-500"
                    : "border-red-500/30 text-red-500"
              )}
            >
              {isAlive ? (
                <>
                  <Wifi className="mr-1 h-3 w-3" />
                  Connected
                </>
              ) : status === "connecting" ? (
                <>
                  <Radio className="mr-1 h-3 w-3 animate-pulse" />
                  Connecting
                </>
              ) : (
                <>
                  <WifiOff className="mr-1 h-3 w-3" />
                  Disconnected
                </>
              )}
            </Badge>
            {isPaused && (
              <Badge variant="outline" className="ml-1 text-xs border-amber-500/30 text-amber-500">
                <Pause className="mr-1 h-3 w-3" />
                Paused
              </Badge>
            )}
          </DialogTitle>
          <DialogDescription>
            Real-time event stream from the local agent
          </DialogDescription>
        </DialogHeader>

        {/* Toolbar */}
        <div className="flex items-center gap-2 border-b pb-2">
          {/* Filter input */}
          <div className="relative flex-1">
            <input
              type="text"
              placeholder="Filter events..."
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              className="w-full h-8 px-3 text-sm bg-muted/50 border border-transparent rounded-md focus:border-ring focus:outline-none"
            />
          </div>

          {/* Pause/Resume */}
          <Button
            variant={isPaused ? "default" : "outline"}
            size="sm"
            onClick={() => setIsPaused(!isPaused)}
          >
            {isPaused ? (
              <>
                <Play className="mr-1.5 h-3.5 w-3.5" />
                Resume
              </>
            ) : (
              <>
                <Pause className="mr-1.5 h-3.5 w-3.5" />
                Pause
              </>
            )}
          </Button>

          {/* Clear */}
          <Button variant="outline" size="sm" onClick={clearLogs}>
            <Trash2 className="mr-1.5 h-3.5 w-3.5" />
            Clear
          </Button>

          {/* Copy */}
          <Button variant="outline" size="sm" onClick={copyLogs} disabled={logs.length === 0}>
            <Copy className="mr-1.5 h-3.5 w-3.5" />
            Copy
          </Button>

          {/* Download */}
          <Button variant="outline" size="sm" onClick={downloadLogs} disabled={logs.length === 0}>
            <Download className="mr-1.5 h-3.5 w-3.5" />
            Export
          </Button>
        </div>

        {/* Output container */}
        <div
          ref={outputRef}
          onScroll={handleScroll}
          className="flex-1 overflow-auto bg-black/90 rounded-lg p-4 font-mono text-xs min-h-[300px] max-h-[500px]"
        >
          {filteredLogs.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-muted-foreground">
              <Terminal className="h-8 w-8 mb-2" />
              <p>{logs.length === 0 ? "Waiting for events..." : "No matching events"}</p>
              {lastHeartbeat && (
                <p className="text-xs mt-2 opacity-50">
                  Last heartbeat: {new Date(lastHeartbeat).toLocaleTimeString()}
                </p>
              )}
            </div>
          ) : (
            <div className="space-y-0.5">
              {filteredLogs.map((log) => (
                <div
                  key={log.id}
                  className={cn(
                    "flex gap-2 hover:bg-white/5 rounded px-1 -mx-1 py-0.5",
                    log.event === "ping" && "opacity-30"
                  )}
                >
                  <span className="text-muted-foreground/50 shrink-0">
                    {formatTime(log.timestamp)}
                  </span>
                  <span className={cn("shrink-0 font-semibold", getEventColor(log.event))}>
                    {log.event}
                  </span>
                  <span className="text-green-400/80 truncate flex-1">
                    {typeof log.data === "string" 
                      ? log.data 
                      : JSON.stringify(log.data)
                    }
                  </span>
                </div>
              ))}
              {!isPaused && (
                <span className="inline-block w-2 h-4 bg-green-400 animate-pulse ml-1" />
              )}
            </div>
          )}
        </div>

        {/* Footer stats */}
        <div className="flex items-center justify-between pt-2 border-t text-xs text-muted-foreground">
          <div className="flex items-center gap-4">
            <span>{filteredLogs.length} events{filter && ` (filtered from ${logs.length})`}</span>
            {!autoScroll && (
              <Button
                variant="ghost"
                size="sm"
                className="h-6 text-xs"
                onClick={() => {
                  setAutoScroll(true);
                  if (outputRef.current) {
                    outputRef.current.scrollTop = outputRef.current.scrollHeight;
                  }
                }}
              >
                Scroll to bottom
              </Button>
            )}
          </div>
          <div>
            {lastHeartbeat && (
              <span>Last ping: {new Date(lastHeartbeat).toLocaleTimeString()}</span>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
