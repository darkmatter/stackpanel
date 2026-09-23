"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { BellRing, Sparkles } from "lucide-react";
import { HealthSummaryPanel } from "@/lib/healthchecks";
import { StatsGrid } from "@/components/studio/overview/stats-grid";
import { ServicesStatusCard } from "@/components/studio/overview/services-status-card";
import { ProcessStateCard } from "@/components/studio/overview/process-state-card";
import { FEATURE_FLAG_KEYS, useFeatureFlags } from "@gen/featureflags";

export function OverviewPanel() {
  const { getVariant, isEnabled } = useFeatureFlags();
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

      {/* Security Status (AWS Session & Certificates) */}
      {/*<SecurityStatusCard />*/}

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

      {/* Stats Grid - Real data */}
      <StatsGrid />

      {/* Health Summary */}
      <HealthSummaryPanel />
    </div>
  );
}
