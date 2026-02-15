import { useCallback, useEffect, useMemo, useState } from "react";
import {
  CheckCircle2,
  XCircle,
  RefreshCw,
  Loader2,
  FileCheck,
  ShieldCheck,
} from "lucide-react";
import { Button } from "@ui/button";
import { useSetupContext } from "../setup-context";
import { useAgentClient } from "@/lib/agent-provider";
import { useNixConfigQuery } from "@/lib/use-agent";

interface VerifyResult {
  group: string;
  status: "pending" | "checking" | "pass" | "fail";
  error?: string;
}

export function VerifyConfigStep() {
  const { isConnected, goToStep } = useSetupContext();
  const agentClient = useAgentClient();
  const { data: nixConfig } = useNixConfigQuery();
  const [sopsExists, setSopsExists] = useState<boolean | null>(null);
  const [checkingSops, setCheckingSops] = useState(false);
  const [verifyResults, setVerifyResults] = useState<VerifyResult[]>([]);
  const [isVerifying, setIsVerifying] = useState(false);

  const secretsConfig = (nixConfig?.config as Record<string, unknown>)
    ?.secrets as Record<string, unknown> | undefined;
  const groupsConfig = secretsConfig?.groups as
    | Record<string, Record<string, unknown>>
    | undefined;

  const groups = useMemo(
    () =>
      groupsConfig
        ? Object.keys(groupsConfig).filter(
            (g) => groupsConfig[g]?.["age-pub"],
          )
        : [],
    [groupsConfig],
  );

  const checkSopsConfig = useCallback(async () => {
    if (!agentClient || !isConnected) return;
    setCheckingSops(true);
    try {
      const res = await agentClient.readFile(
        ".stackpanel/secrets/groups/.sops.yaml",
      );
      setSopsExists(!!res);
    } catch {
      setSopsExists(false);
    } finally {
      setCheckingSops(false);
    }
  }, [agentClient, isConnected]);

  const runVerification = useCallback(async () => {
    if (!agentClient || !isConnected || groups.length === 0) return;
    setIsVerifying(true);
    const results: VerifyResult[] = groups.map((g) => ({
      group: g,
      status: "checking" as const,
    }));
    setVerifyResults([...results]);

    for (let i = 0; i < groups.length; i++) {
      try {
        const res = await agentClient.verifySecrets(groups[i]);
        results[i] = {
          group: groups[i],
          status: res.success ? "pass" : "fail",
          error: res.error,
        };
      } catch (err) {
        results[i] = {
          group: groups[i],
          status: "fail",
          error: err instanceof Error ? err.message : "Unknown error",
        };
      }
      setVerifyResults([...results]);
    }
    setIsVerifying(false);
  }, [agentClient, isConnected, groups]);

  useEffect(() => {
    checkSopsConfig();
  }, [checkSopsConfig]);

  const allPassed =
    verifyResults.length > 0 &&
    verifyResults.every((r) => r.status === "pass");

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Verify that your secrets configuration is working correctly. The SOPS
        config is auto-generated from your Nix configuration at shell entry.
      </p>

      {/* SOPS Config Status */}
      <div className="rounded-lg border p-4 space-y-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <FileCheck className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm font-medium">
              groups/.sops.yaml (auto-generated)
            </span>
          </div>
          {checkingSops ? (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          ) : sopsExists ? (
            <CheckCircle2 className="h-4 w-4 text-green-500" />
          ) : sopsExists === false ? (
            <XCircle className="h-4 w-4 text-red-500" />
          ) : null}
        </div>
        {sopsExists === false && (
          <p className="text-xs text-amber-600">
            Not found. Enter the devshell to auto-generate it from your Nix
            config.
          </p>
        )}
        {sopsExists && (
          <p className="text-xs text-muted-foreground">
            Generated from config.nix group public keys. This file is gitignored
            and regenerated on every shell entry.
          </p>
        )}
      </div>

      {/* Encrypt/Decrypt Verification */}
      {groups.length > 0 && (
        <div className="rounded-lg border p-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <ShieldCheck className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm font-medium">
                Encrypt/Decrypt Round-Trip
              </span>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={runVerification}
              disabled={isVerifying || !isConnected}
            >
              {isVerifying ? (
                <Loader2 className="h-3 w-3 animate-spin mr-1" />
              ) : (
                <RefreshCw className="h-3 w-3 mr-1" />
              )}
              {verifyResults.length > 0 ? "Re-verify" : "Verify"}
            </Button>
          </div>

          {verifyResults.length > 0 && (
            <div className="space-y-2">
              {verifyResults.map((r) => (
                <div
                  key={r.group}
                  className="flex items-center justify-between text-sm py-1"
                >
                  <span className="font-mono text-xs">{r.group}</span>
                  {r.status === "checking" && (
                    <Loader2 className="h-3 w-3 animate-spin text-muted-foreground" />
                  )}
                  {r.status === "pass" && (
                    <span className="text-green-600 flex items-center gap-1">
                      <CheckCircle2 className="h-3 w-3" /> Pass
                    </span>
                  )}
                  {r.status === "fail" && (
                    <span
                      className="text-red-600 flex items-center gap-1"
                      title={r.error}
                    >
                      <XCircle className="h-3 w-3" /> Failed
                    </span>
                  )}
                </div>
              ))}
            </div>
          )}

          {verifyResults.length === 0 && (
            <p className="text-xs text-muted-foreground">
              Click Verify to test encrypt/decrypt for each initialized group.
            </p>
          )}
        </div>
      )}

      {groups.length === 0 && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/30 p-3">
          <p className="text-sm text-amber-700 dark:text-amber-400">
            No groups initialized yet.{" "}
            <button
              className="underline font-medium"
              onClick={() => goToStep("init-groups")}
            >
              Initialize a group first
            </button>
          </p>
        </div>
      )}

      {allPassed && (
        <div className="rounded-lg border border-green-200 bg-green-50 dark:border-green-800 dark:bg-green-950/30 p-3">
          <p className="text-sm text-green-700 dark:text-green-400 font-medium">
            All groups verified. Your secrets configuration is working
            correctly.
          </p>
        </div>
      )}
    </div>
  );
}
