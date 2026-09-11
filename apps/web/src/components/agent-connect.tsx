"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Loader2, Settings, Unplug, Wifi } from "lucide-react";
import { useEffect, useState } from "react";
import { useAgentEndpoint } from "@/lib/agent-endpoint";
import { useAgentContext } from "@/lib/agent-provider";

export function AgentConnect({ onConnected }: { onConnected?: () => void; overlay?: boolean }) {
  const {
    healthStatus,
    isConnected,
    isPairing,
    pairingError,
    projectRoot,
    pair,
    clearPairing,
    host,
    port,
  } = useAgentContext();
  const { useLocal, useDemo, bootingDemo } = useAgentEndpoint();
  const [settings, setSettings] = useState(false);
  const [nextHost, setNextHost] = useState(host);
  const [nextPort, setNextPort] = useState(String(port));
  useEffect(() => {
    if (isConnected) onConnected?.();
  }, [isConnected, onConnected]);
  return (
    <Card>
      <CardHeader>
        <CardTitle>{isConnected ? "Connected to Agent" : "Connect to your local agent"}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p>
          {host}:{port}
          {projectRoot ? ` · ${projectRoot}` : ""}
        </p>
        {healthStatus === "checking" ? <p role="status">Checking local agent…</p> : null}
        {healthStatus === "unavailable" ? (
          <p role="status">
            Agent unavailable. Start <code>stack agent</code> in your repository devshell, then
            retry.
          </p>
        ) : null}
        {pairingError ? (
          <p role="alert" className="text-destructive">
            {pairingError}
          </p>
        ) : null}
        {isConnected ? (
          <Button onClick={clearPairing} variant="outline">
            <Unplug className="mr-2 h-4 w-4" />
            Disconnect
          </Button>
        ) : (
          <Button onClick={pair} disabled={healthStatus !== "available" || isPairing}>
            {isPairing ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Wifi className="mr-2 h-4 w-4" />
            )}
            {isPairing ? "Complete pairing in your browser…" : "Connect to Agent"}
          </Button>
        )}
        <Button variant="ghost" onClick={() => setSettings(!settings)}>
          <Settings className="mr-2 h-4 w-4" />
          Connection settings
        </Button>
        {settings ? (
          <form
            className="space-y-2"
            onSubmit={(event) => {
              event.preventDefault();
              const parsed = Number(nextPort);
              if (!nextHost.trim() || !Number.isInteger(parsed) || parsed < 1 || parsed > 65535)
                return;
              clearPairing();
              useLocal({ host: nextHost.trim(), port: parsed });
              setSettings(false);
            }}
          >
            <Label htmlFor="agent-host">Agent host</Label>
            <Input id="agent-host" value={nextHost} onChange={(e) => setNextHost(e.target.value)} />
            <Label htmlFor="agent-port">Agent port</Label>
            <Input
              id="agent-port"
              type="number"
              min={1}
              max={65535}
              value={nextPort}
              onChange={(e) => setNextPort(e.target.value)}
            />
            <Button type="submit">Save connection</Button>
          </form>
        ) : null}
        {!isConnected ? (
          <Button variant="ghost" disabled={bootingDemo} onClick={() => void useDemo()}>
            Try the demo
          </Button>
        ) : null}
      </CardContent>
    </Card>
  );
}

/**
 * Compact status indicator for headers/sidebars
 *
 * Uses token presence (not WebSocket state) to determine "connected" status,
 * since most functionality uses HTTP+tRPC with token auth.
 */
export function AgentStatus() {
  const { healthStatus, isAuthenticated } = useAgentContext();

  // Agent health check in progress
  if (healthStatus === "checking") {
    return (
      <div className="flex items-center gap-2 text-muted-foreground text-xs">
        <Loader2 className="h-3 w-3 animate-spin" />
        <span>Checking...</span>
      </div>
    );
  }

  // Agent not reachable
  if (healthStatus === "unavailable") {
    return (
      <div className="flex items-center gap-2 text-destructive text-xs">
        <div className="h-2 w-2 rounded-full bg-destructive" />
        <span>Agent offline</span>
      </div>
    );
  }

  // Agent available and we have a valid token (paired)
  if (isAuthenticated) {
    return (
      <div className="flex items-center gap-2 text-emerald-500 text-xs">
        <div className="h-2 w-2 rounded-full bg-emerald-500" />
        <span>Connected</span>
      </div>
    );
  }

  // Agent available but no token (not paired)
  return (
    <div className="flex items-center gap-2 text-yellow-500 text-xs">
      <div className="h-2 w-2 rounded-full bg-yellow-500" />
      <span>Not paired</span>
    </div>
  );
}
