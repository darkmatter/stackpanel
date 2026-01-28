"use client";

import { Link } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Database, KeyRound, Server, Terminal } from "lucide-react";
import { SecurityStatusCard as _SecurityStatusCard } from "@/components/studio/security-status-card";
import { HealthSummaryPanel } from "@/lib/healthchecks";
import { StatsGrid } from "@/components/studio/overview/stats-grid";
import { ServicesStatusCard } from "@/components/studio/overview/services-status-card";
import { ProcessStateCard } from "@/components/studio/overview/process-state-card";

export function OverviewPanel() {
  return (
    <div className="space-y-6">
      {/* Security Status (AWS Session & Certificates) */}
      {/*<SecurityStatusCard />*/}

      {/* Two-column layout for Process State and Services */}
      <div className="grid gap-6 lg:grid-cols-2">
        {/* Process Compose State */}
        <ProcessStateCard />

        {/* Services Status */}
        <ServicesStatusCard />
      </div>

      {/* Stats Grid - Real data */}
      <StatsGrid />

      {/* Quick Actions */}
      {/* <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="font-medium text-base">
              Quick Actions
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid gap-3 sm:grid-cols-2">
              <Link to="/studio/services">
                <Button
                  className="h-auto w-full flex-col gap-2 bg-transparent py-4"
                  variant="outline"
                >
                  <Server className="h-5 w-5 text-accent" />
                  <span>Manage Services</span>
                </Button>
              </Link>
              <Link to="/studio/databases">
                <Button
                  className="h-auto w-full flex-col gap-2 bg-transparent py-4"
                  variant="outline"
                >
                  <Database className="h-5 w-5 text-accent" />
                  <span>Databases</span>
                </Button>
              </Link>
              <Link to="/studio/secrets">
                <Button
                  className="h-auto w-full flex-col gap-2 bg-transparent py-4"
                  variant="outline"
                >
                  <KeyRound className="h-5 w-5 text-accent" />
                  <span>Secrets</span>
                </Button>
              </Link>
              <Link to="/studio/terminal">
                <Button
                  className="h-auto w-full flex-col gap-2 bg-transparent py-4"
                  variant="outline"
                >
                  <Terminal className="h-5 w-5 text-accent" />
                  <span>Terminal</span>
                </Button>
              </Link>
            </div>
          </CardContent>
        </Card>
      </div> */}

      {/* Health Summary */}
      <HealthSummaryPanel />
    </div>
  );
}
