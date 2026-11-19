import { Badge } from "@ui/badge";
import {
  Check,
  Cloud,
  Code,
  FileCode,
  Heart,
  Key,
  Package,
  Settings,
  Terminal,
  XCircle,
} from "lucide-react";
import { cn } from "@/lib/utils";
import type { Module } from "@stackpanel/proto/agent/v1/module";

const features = [
  { key: "files", icon: FileCode, label: "Files" },
  { key: "scripts", icon: Terminal, label: "Scripts" },
  { key: "healthchecks", icon: Heart, label: "Health Checks" },
  { key: "services", icon: Cloud, label: "Services" },
  { key: "secrets", icon: Key, label: "Secrets" },
  { key: "packages", icon: Package, label: "Packages" },
  { key: "tasks", icon: Code, label: "Tasks" },
  { key: "appModule", icon: Settings, label: "App Config" },
] as const;

export function ModuleFeatures({
  values,
  compact = false,
}: {
  values: Module["features"];
  compact?: boolean;
}) {
  if (!values) return <p>Module feature information is unavailable.</p>;
  const visible = compact ? features.filter(({ key }) => values[key]) : features;
  return (
    <section>
      <h4 className="mb-2 text-sm font-medium">Features</h4>
      <div className={compact ? "flex flex-wrap gap-1" : "grid grid-cols-2 gap-2"}>
        {!visible.length && <p className="text-sm text-muted-foreground">No features declared</p>}
        {visible.map(({ key, icon: Icon, label }) =>
          compact ? (
            <Badge key={key} variant="outline" className="gap-1 px-1.5 py-0.5 text-xs">
              <Icon className="h-3 w-3" />
              {label}
            </Badge>
          ) : (
            <div
              key={key}
              className={cn(
                "flex items-center gap-2 rounded-md border px-3 py-2 text-sm",
                values[key]
                  ? "border-green-500/30 bg-green-500/5"
                  : "border-muted bg-muted/30 opacity-50",
              )}
            >
              {values[key] ? (
                <Check aria-label="Provided" className="h-3.5 w-3.5 text-green-500" />
              ) : (
                <XCircle aria-label="Not provided" className="h-3.5 w-3.5 text-muted-foreground" />
              )}
              <Icon className="h-3.5 w-3.5" />
              {label}
            </div>
          ),
        )}
      </div>
    </section>
  );
}
