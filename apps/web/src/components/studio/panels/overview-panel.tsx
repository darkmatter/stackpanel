"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { BellRing, Sparkles } from "lucide-react";
import { HealthSummaryPanel } from "@/lib/healthchecks";
import { useAgentContext } from "@/lib/agent-provider";
import { StatsGrid } from "@/components/studio/overview/stats-grid";
import { ServicesStatusCard } from "@/components/studio/overview/services-status-card";
import { ProcessStateCard } from "@/components/studio/overview/process-state-card";
import { FEATURE_FLAG_KEYS, useFeatureFlags } from "@gen/featureflags";
import { StudioPanel } from "./shared/studio-panel";
import { studioPanelKey, useStudioPanels } from "./shared/use-studio-panels";

export function OverviewPanel() {
  const { getVariant, isEnabled } = useFeatureFlags();
  const { isConnected } = useAgentContext();
  const { config, panels, isLoading, error } = useStudioPanels();
  const overviewPanels = panels.filter((panel) => panel.enabled && panel.slot === "overview");
  const layout = getVariant(FEATURE_FLAG_KEYS.overviewLayout, "classic");
  const showPulseBanner = isEnabled(FEATURE_FLAG_KEYS.overviewPulseBanner);
  const isCompact = layout === "compact";

  return (
    <div className="space-y-6">
      {showPulseBanner && (
        <Card className="border-accent/30 bg-accent/5">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Sparkles className="h-4 w-4" />
              New overview variation active
            </CardTitle>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground flex items-center gap-2">
            <BellRing className="h-4 w-4" />
            Feature flag pulse banner is currently enabled in Studio overview.
          </CardContent>
        </Card>
      )}

      {/* Two-column layout for Process State and Services */}
      <div
        className={isCompact
          ? "grid gap-4 lg:grid-cols-2"
          : "grid gap-6 lg:grid-cols-2"}
      >
        {/* Process Compose State */}
        <ProcessStateCard />

        {/* Services Status */}
        <ServicesStatusCard />
      </div>

      {isConnected && (error ? (
        <p role="alert" className="text-sm text-destructive">
          Could not load module overview panels: {error.message}
        </p>
      ) : isLoading ? (
        <p role="status" className="text-sm text-muted-foreground">Loading module overview panels…</p>
      ) : !config ? (
        <p role="status" className="text-sm text-muted-foreground">Module overview panels are unavailable.</p>
      ) : null)}

      {isConnected && !isLoading && !error && overviewPanels.length > 0 && (
        <div className={isCompact ? "grid gap-4 lg:grid-cols-2" : "grid gap-6 lg:grid-cols-2"}>
          {overviewPanels.map((panel) => (
            <StudioPanel key={studioPanelKey(panel)} panel={panel} />
          ))}
        </div>
      )}

      {/* Stats Grid - Real data */}
      <StatsGrid />

      {/* Health Summary */}
      <HealthSummaryPanel />
    </div>
  );
}
