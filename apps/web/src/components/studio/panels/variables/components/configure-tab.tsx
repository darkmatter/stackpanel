"use client";

import { GroupsSection } from "../groups-section";
import { KMSSettings } from "../edit-secret-dialog";
import { Badge } from "@/components/ui/badge";

interface ConfigureTabProps {
  isChamber: boolean;
  backendData?: {
    chamber?: {
      servicePrefix?: string;
    };
  } | null;
}

export function ConfigureTab({ isChamber, backendData }: ConfigureTabProps) {
  return (
    <div className="mt-6 space-y-6">
      {isChamber && (
        <div className="flex items-center gap-2 rounded-lg border bg-muted/40 px-4 py-3 text-sm text-muted-foreground">
          <Badge variant="secondary">Chamber</Badge>
          <span>
            Secrets are stored in AWS SSM Parameter Store.
            {backendData?.chamber?.servicePrefix && (
              <span> Prefix: <code className="font-mono">{backendData.chamber.servicePrefix}</code></span>
            )}
          </span>
        </div>
      )}

      <GroupsSection />

      <div className="space-y-4">
        <KMSSettings />
      </div>
    </div>
  );
}
