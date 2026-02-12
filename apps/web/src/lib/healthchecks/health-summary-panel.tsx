/**
 * HealthSummaryPanel Component
 *
 * A panel component that displays the health status of all modules
 * with their individual healthchecks. Shows a traffic light for each
 * module and allows running healthchecks.
 *
 * Scripts are displayed as documentation to show what each check does.
 *
 * Usage:
 *   import { HealthSummaryPanel } from '@/lib/healthchecks';
 *
 *   <HealthSummaryPanel />
 */

import { cn } from "@/lib/utils";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";

import {
  ChevronDown,
  ChevronRight,
  RefreshCw,
  Clock,
  Activity,
  Terminal,
  Globe,
  Network,
  FileCode,
  AlertCircle,
  CheckCircle2,
  Copy,
  Check,
} from "lucide-react";
import { useState } from "react";
import type {
  HealthSummaryPanelProps,
  ModuleHealth,
  HealthcheckResult,
} from "./types";
import { STATUS_DISPLAY } from "./types";
import {
  TrafficLight,
  TrafficLightBadge,
  TrafficLightDot,
} from "./traffic-light";
import { useHealthchecks, countModulesByStatus } from "./use-healthchecks";

// =============================================================================
// HealthSummaryPanel Component
// =============================================================================

/**
 * Main health summary panel component.
 * Fetches and displays health status for all modules.
 */
export function HealthSummaryPanel() {
  const {
    data: summary,
    isLoading,
    error,
    isRefreshing,
    refetch,
    runChecks,
  } = useHealthchecks({ enabled: true });

  return (
    <HealthSummaryPanelView
      summary={summary}
      isLoading={isLoading}
      error={error ?? undefined}
      isRefreshing={isRefreshing}
      onRefresh={refetch}
      onRunChecks={runChecks}
    />
  );
}

// =============================================================================
// HealthSummaryPanelView Component (Presentational)
// =============================================================================

interface HealthSummaryPanelViewProps extends HealthSummaryPanelProps {
  isRefreshing?: boolean;
  onRunChecks?: (module?: string, checkId?: string) => Promise<void>;
}

/**
 * Presentational component for the health summary panel.
 * Can be used with custom data sources.
 */
export function HealthSummaryPanelView({
  summary,
  isLoading,
  error,
  isRefreshing,
  onRunChecks,
}: HealthSummaryPanelViewProps) {
  const counts = countModulesByStatus(summary);
  const moduleCount = summary?.modules
    ? Object.keys(summary.modules).length
    : 0;

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Activity className="h-5 w-5 text-muted-foreground" />
            <div>
              <CardTitle className="text-lg">System Health</CardTitle>
              <CardDescription className="text-sm">
                {moduleCount > 0
                  ? `${moduleCount} modules monitored`
                  : "No healthchecks configured"}
              </CardDescription>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {summary && summary.overallStatus && (
              <TrafficLightBadge
                status={summary.overallStatus}
                size="md"
                showLabel
              />
            )}
            <Button
              variant="outline"
              size="sm"
              onClick={() => onRunChecks?.()}
              disabled={isLoading || isRefreshing}
              className="gap-2"
            >
              <RefreshCw
                className={cn("h-4 w-4", isRefreshing && "animate-spin")}
              />
              Run Checks
            </Button>
          </div>
        </div>
      </CardHeader>

      <CardContent>
        {error && (
          <div className="mb-4 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-400">
            {error}
          </div>
        )}

        {isLoading && !summary ? (
          <HealthSummarySkeleton />
        ) : summary?.modules && moduleCount > 0 ? (
          <div className="space-y-4">
            {/* Quick status overview */}
            <div className="flex flex-wrap gap-3 border-b pb-4">
              <StatusCount
                label="Healthy"
                count={counts.healthy}
                status="HEALTH_STATUS_HEALTHY"
              />
              <StatusCount
                label="Degraded"
                count={counts.degraded}
                status="HEALTH_STATUS_DEGRADED"
              />
              <StatusCount
                label="Unhealthy"
                count={counts.unhealthy}
                status="HEALTH_STATUS_UNHEALTHY"
              />
              {counts.unknown > 0 && (
                <StatusCount
                  label="Unknown"
                  count={counts.unknown}
                  status="HEALTH_STATUS_UNKNOWN"
                />
              )}
            </div>

            {/* Module health cards */}
            <div className="space-y-3">
              {Object.entries(summary.modules).map(
                ([moduleName, moduleHealth]) => (
                  <ModuleHealthCard
                    key={moduleName}
                    moduleHealth={moduleHealth}
                    onRunChecks={() => onRunChecks?.(moduleName)}
                    onRunCheck={
                      onRunChecks
                        ? (checkId: string) => onRunChecks(moduleName, checkId)
                        : undefined
                    }
                  />
                ),
              )}
            </div>

            {/* Last updated timestamp */}
            {summary.lastUpdated && (
              <div className="flex items-center gap-1.5 pt-2 text-xs text-muted-foreground">
                <Clock className="h-3 w-3" />
                Last updated:{" "}
                {new Date(summary.lastUpdated).toLocaleTimeString()}
              </div>
            )}
          </div>
        ) : (
          <div className="py-8 text-center text-muted-foreground">
            <Activity className="mx-auto mb-3 h-8 w-8 opacity-50" />
            <p>No healthchecks configured</p>
            <p className="mt-1 text-sm">
              Add healthchecks to your modules to monitor their status.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// =============================================================================
// StatusCount Component
// =============================================================================

function StatusCount({
  label,
  count,
  status,
}: {
  label: string;
  count: number;
  status: keyof typeof STATUS_DISPLAY;
}) {
  if (count === 0) return null;

  return (
    <div className="flex items-center gap-1.5 text-sm">
      <TrafficLightDot status={status} size="sm" />
      <span className="text-muted-foreground">{label}:</span>
      <span className="font-medium">{count}</span>
    </div>
  );
}

// =============================================================================
// ModuleHealthCard Component
// =============================================================================

interface ModuleHealthCardProps {
  moduleHealth: ModuleHealth;
  onRunChecks?: () => void;
  onRunCheck?: (checkId: string) => Promise<void>;
}

function ModuleHealthCard({
  moduleHealth,
  onRunChecks,
  onRunCheck,
}: ModuleHealthCardProps) {
  const [isOpen, setIsOpen] = useState(false);
  const hasChecks = moduleHealth.checks?.length > 0;
  const status = moduleHealth.status || "HEALTH_STATUS_UNKNOWN";

  return (
    <Collapsible open={isOpen} onOpenChange={setIsOpen}>
      <div
        className={cn(
          "rounded-lg border",
          status === "HEALTH_STATUS_HEALTHY" &&
            "border-green-200 dark:border-green-900",
          status === "HEALTH_STATUS_DEGRADED" &&
            "border-yellow-200 dark:border-yellow-900",
          status === "HEALTH_STATUS_UNHEALTHY" &&
            "border-red-200 dark:border-red-900",
          (status === "HEALTH_STATUS_UNKNOWN" ||
            status === "HEALTH_STATUS_UNSPECIFIED") &&
            "border-muted",
        )}
      >
        <CollapsibleTrigger asChild>
          <button
            type="button"
            className={cn(
              "flex w-full items-center justify-between p-3",
              "hover:bg-muted/50 transition-colors rounded-lg",
              hasChecks && "cursor-pointer",
            )}
            disabled={!hasChecks}
          >
            <div className="flex items-center gap-3">
              <TrafficLight status={status} size="md" />
              <div className="text-left">
                <div className="font-medium">{moduleHealth.displayName}</div>
                <div className="text-xs text-muted-foreground">
                  {moduleHealth.healthyCount ?? 0}/
                  {moduleHealth.totalCount ?? 0} checks passing
                </div>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {hasChecks &&
                (isOpen ? (
                  <ChevronDown className="h-4 w-4 text-muted-foreground" />
                ) : (
                  <ChevronRight className="h-4 w-4 text-muted-foreground" />
                ))}
            </div>
          </button>
        </CollapsibleTrigger>

        {hasChecks && (
          <CollapsibleContent>
            <div className="border-t">
              <div className="divide-y">
                {(moduleHealth.checks ?? []).map((checkResult) => (
                  <HealthcheckItem
                    key={checkResult.checkId}
                    result={checkResult}
                    onRunCheck={onRunCheck}
                  />
                ))}
              </div>
              {onRunChecks && (
                <div className="border-t p-3">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      onRunChecks();
                    }}
                    className="h-7 text-xs"
                  >
                    <RefreshCw className="mr-1 h-3 w-3" />
                    Re-run all checks
                  </Button>
                </div>
              )}
            </div>
          </CollapsibleContent>
        )}
      </div>
    </Collapsible>
  );
}

// =============================================================================
// HealthcheckItem Component - Shows individual check with script
// =============================================================================

function HealthcheckItem({
  result,
  onRunCheck,
}: {
  result: HealthcheckResult;
  onRunCheck?: (checkId: string) => Promise<void>;
}) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const check = result.check;
  const status = result.status || "HEALTH_STATUS_UNKNOWN";

  // Extract display name from check or parse from ID
  const checkName =
    check?.name ||
    result.checkId.split("-").slice(1).join(" ") ||
    result.checkId;
  const description = check?.description;
  const severity = check?.severity;

  // Determine what type of check this is and get the content
  const checkType = check?.type || "HEALTHCHECK_TYPE_SCRIPT";
  const scriptContent = check?.script;
  const httpUrl = check?.httpUrl;
  const tcpHost = check?.tcpHost;
  const tcpPort = check?.tcpPort;
  const nixExpr = check?.nixExpr;

  const hasDetails =
    scriptContent ||
    httpUrl ||
    tcpHost ||
    nixExpr ||
    result.output ||
    result.error;

  return (
    <Collapsible open={isExpanded} onOpenChange={setIsExpanded}>
      <div className="flex items-start">
        <CollapsibleTrigger asChild>
          <button
            type="button"
            className={cn(
              "flex w-full items-start gap-3 p-3 text-left transition-colors",
              hasDetails && "hover:bg-muted/30 cursor-pointer",
            )}
          >
            <div className="mt-0.5">
              <TrafficLightDot status={status} size="sm" />
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-medium text-sm">{checkName}</span>
                {severity && <SeverityBadge severity={severity} />}
                <CheckTypeBadge type={checkType} />
                {result.durationMs > 0 && (
                  <span className="text-xs text-muted-foreground">
                    {result.durationMs}ms
                  </span>
                )}
              </div>
              {description && (
                <p className="text-xs text-muted-foreground mt-0.5">
                  {description}
                </p>
              )}
              {/* Show error inline if not expanded */}
              {!isExpanded && result.error && (
                <p className="text-xs text-red-500 dark:text-red-400 mt-1 line-clamp-1">
                  {result.error}
                </p>
              )}
            </div>
            {hasDetails && (
              <div className="mt-0.5">
                {isExpanded ? (
                  <ChevronDown className="h-4 w-4 text-muted-foreground" />
                ) : (
                  <ChevronRight className="h-4 w-4 text-muted-foreground" />
                )}
              </div>
            )}
          </button>
        </CollapsibleTrigger>
        {onRunCheck && (
          <Button
            variant="ghost"
            size="sm"
            className="h-6 w-6 p-0 mt-3 mr-3 shrink-0 text-muted-foreground hover:text-foreground"
            disabled={isRunning}
            onClick={async (e) => {
              e.stopPropagation();
              setIsRunning(true);
              try {
                await onRunCheck(result.checkId);
              } finally {
                setIsRunning(false);
              }
            }}
          >
            <RefreshCw
              className={cn("h-3 w-3", isRunning && "animate-spin")}
            />
          </Button>
        )}
      </div>

      {hasDetails && (
        <CollapsibleContent>
          <div className="px-3 pb-3 space-y-3">
            {/* Script content */}
            {scriptContent && (
              <ScriptBlock
                title="Script"
                content={scriptContent}
                language="bash"
              />
            )}

            {/* Nix expression */}
            {nixExpr && (
              <ScriptBlock
                title="Nix Expression"
                content={nixExpr}
                language="nix"
              />
            )}

            {/* HTTP check details */}
            {httpUrl && (
              <div className="rounded-md border bg-muted/30 p-3">
                <div className="flex items-center gap-2 text-xs text-muted-foreground mb-2">
                  <Globe className="h-3.5 w-3.5" />
                  <span className="font-medium">HTTP Check</span>
                </div>
                <div className="text-sm font-mono">
                  {check?.httpMethod || "GET"} {httpUrl}
                </div>
                {check?.httpExpectedStatus && (
                  <div className="text-xs text-muted-foreground mt-1">
                    Expected status: {check.httpExpectedStatus}
                  </div>
                )}
              </div>
            )}

            {/* TCP check details */}
            {tcpHost && tcpPort && (
              <div className="rounded-md border bg-muted/30 p-3">
                <div className="flex items-center gap-2 text-xs text-muted-foreground mb-2">
                  <Network className="h-3.5 w-3.5" />
                  <span className="font-medium">TCP Check</span>
                </div>
                <div className="text-sm font-mono">
                  {tcpHost}:{tcpPort}
                </div>
              </div>
            )}

            {/* Output */}
            {result.output && (
              <div className="rounded-md border bg-green-50 dark:bg-green-950/30 p-3">
                <div className="flex items-center gap-2 text-xs text-green-700 dark:text-green-400 mb-2">
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  <span className="font-medium">Output</span>
                </div>
                <pre className="text-xs font-mono whitespace-pre-wrap text-green-800 dark:text-green-300">
                  {result.output}
                </pre>
              </div>
            )}

            {/* Error */}
            {result.error && (
              <div className="rounded-md border border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-950/30 p-3">
                <div className="flex items-center gap-2 text-xs text-red-700 dark:text-red-400 mb-2">
                  <AlertCircle className="h-3.5 w-3.5" />
                  <span className="font-medium">Error</span>
                </div>
                <pre className="text-xs font-mono whitespace-pre-wrap text-red-800 dark:text-red-300">
                  {result.error}
                </pre>
              </div>
            )}
          </div>
        </CollapsibleContent>
      )}
    </Collapsible>
  );
}

// =============================================================================
// ScriptBlock Component - Displays script with syntax highlighting feel
// =============================================================================

function ScriptBlock({
  title,
  content,
  language,
}: {
  title: string;
  content: string;
  language: "bash" | "nix";
}) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async (e: React.MouseEvent) => {
    e.stopPropagation();
    await navigator.clipboard.writeText(content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="rounded-md border bg-slate-950 dark:bg-slate-900 overflow-hidden">
      <div className="flex items-center justify-between px-3 py-1.5 bg-slate-900 dark:bg-slate-800 border-b border-slate-800">
        <div className="flex items-center gap-2 text-xs text-slate-400">
          {language === "bash" ? (
            <Terminal className="h-3.5 w-3.5" />
          ) : (
            <FileCode className="h-3.5 w-3.5" />
          )}
          <span className="font-medium">{title}</span>
          <Badge
            variant="outline"
            className="text-[10px] px-1.5 py-0 h-4 border-slate-700 text-slate-500"
          >
            {language}
          </Badge>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleCopy}
          className="h-6 w-6 p-0 text-slate-400 hover:text-slate-200 hover:bg-slate-800"
        >
          {copied ? (
            <Check className="h-3 w-3" />
          ) : (
            <Copy className="h-3 w-3" />
          )}
        </Button>
      </div>
      <div className="overflow-auto max-h-64">
        <pre className="p-3 text-xs font-mono text-slate-300 whitespace-pre overflow-x-auto">
          <code>{content.trim()}</code>
        </pre>
      </div>
    </div>
  );
}

// =============================================================================
// Badge Components
// =============================================================================

function SeverityBadge({ severity }: { severity: string }) {
  const config = {
    HEALTHCHECK_SEVERITY_CRITICAL: {
      label: "Critical",
      className: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400",
    },
    HEALTHCHECK_SEVERITY_WARNING: {
      label: "Warning",
      className:
        "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400",
    },
    HEALTHCHECK_SEVERITY_INFO: {
      label: "Info",
      className:
        "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400",
    },
  }[severity] || {
    label: severity,
    className: "bg-muted text-muted-foreground",
  };

  return (
    <Badge
      variant="outline"
      className={cn("text-[10px] px-1.5 py-0 h-4 border-0", config.className)}
    >
      {config.label}
    </Badge>
  );
}

function CheckTypeBadge({ type }: { type: string }) {
  const config = {
    HEALTHCHECK_TYPE_SCRIPT: { label: "Script", icon: Terminal },
    HEALTHCHECK_TYPE_HTTP: { label: "HTTP", icon: Globe },
    HEALTHCHECK_TYPE_TCP: { label: "TCP", icon: Network },
    HEALTHCHECK_TYPE_NIX: { label: "Nix", icon: FileCode },
  }[type] || { label: type, icon: Terminal };

  const Icon = config.icon;

  return (
    <Badge
      variant="outline"
      className="text-[10px] px-1.5 py-0 h-4 gap-1 text-muted-foreground"
    >
      <Icon className="h-2.5 w-2.5" />
      {config.label}
    </Badge>
  );
}

// =============================================================================
// Loading Skeleton
// =============================================================================

function HealthSummarySkeleton() {
  return (
    <div className="space-y-4">
      {/* Status overview skeleton */}
      <div className="flex gap-3 border-b pb-4">
        <Skeleton className="h-5 w-24" />
        <Skeleton className="h-5 w-24" />
        <Skeleton className="h-5 w-24" />
      </div>

      {/* Module cards skeleton */}
      <div className="space-y-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="rounded-lg border p-3">
            <div className="flex items-center gap-3">
              <Skeleton className="h-5 w-5 rounded-full" />
              <div className="space-y-1.5">
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-3 w-24" />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default HealthSummaryPanel;
