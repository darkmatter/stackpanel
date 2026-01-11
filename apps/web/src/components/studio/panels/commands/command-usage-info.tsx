"use client";

import { Badge } from "@/components/ui/badge";
import { useAppsWithTask } from "@/lib/use-nix-config";

interface CommandUsageInfoProps {
  commandId: string;
}

export function CommandUsageInfo({ commandId }: CommandUsageInfoProps) {
  const { data: apps, isLoading } = useAppsWithTask(commandId);

  if (isLoading) {
    return <span className="text-muted-foreground text-xs">Loading...</span>;
  }

  if (!apps || apps.length === 0) {
    return (
      <span className="text-muted-foreground text-xs">Not used by any app</span>
    );
  }

  return (
    <div className="flex flex-wrap gap-1">
      {apps.map((app) => (
        <Badge key={app.id} variant="outline" className="text-xs">
          {app.name}
        </Badge>
      ))}
    </div>
  );
}
