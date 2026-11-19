import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import {
  ChevronRight,
  Cloud,
  FileCode,
  Heart,
  ListChecks,
  Loader2,
  Package,
  Terminal,
  type LucideIcon,
} from "lucide-react";
import { useModuleOutputs } from "./use-modules";

interface OutputItem {
  id: string;
  title: string;
  description?: string;
  detail?: string;
}

function OutputGroup({
  title,
  icon: Icon,
  items,
}: {
  title: string;
  icon: LucideIcon;
  items: OutputItem[];
}) {
  if (!items.length) return null;
  return (
    <section className="space-y-2">
      <h4 className="flex items-center gap-2 text-sm font-medium">
        <Icon className="h-4 w-4 text-muted-foreground" />
        {title}
        <Badge variant="secondary">{items.length}</Badge>
      </h4>
      <ul className="space-y-1">
        {items.map((item) => (
          <li
            key={item.id}
            className="flex items-start gap-2 rounded-md bg-muted/50 px-3 py-2 text-sm"
          >
            <ChevronRight className="mt-0.5 h-3 w-3 shrink-0 text-muted-foreground" />
            <div className="min-w-0 flex-1">
              <code className="break-all text-xs font-medium">{item.title}</code>
              {item.description && (
                <p className="text-xs text-muted-foreground">{item.description}</p>
              )}
            </div>
            {item.detail && (
              <Badge variant="outline" className="text-xs">
                {item.detail}
              </Badge>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

export function ModuleOutputsSection({ moduleId }: { moduleId: string }) {
  const { data, error, refetch, isFetching } = useModuleOutputs(moduleId);
  if (error)
    return (
      <div className="space-y-2">
        <p role="alert" className="text-sm text-destructive">
          Failed to load module outputs: {error.message}
        </p>
        <Button variant="outline" size="sm" disabled={isFetching} onClick={() => void refetch()}>
          Try again
        </Button>
      </div>
    );
  if (!data)
    return (
      <p role="status" className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" />
        Loading outputs…
      </p>
    );
  const { files, scripts, packages, tasks, services, healthchecks } = data;
  if (![files, scripts, packages, tasks, services, healthchecks].some((items) => items.length)) {
    return (
      <p className="text-sm text-muted-foreground">
        No outputs are attributed to this module in the current configuration.
      </p>
    );
  }
  const named = (item: { name: string; description?: string }) => ({
    id: item.name,
    title: item.name,
    description: item.description,
  });
  return (
    <div className="space-y-4">
      <OutputGroup
        title="Generated Files"
        icon={FileCode}
        items={files.map((f) => ({
          id: f.path,
          title: f.path,
          description: f.description,
          detail: f.type,
        }))}
      />
      <OutputGroup title="Scripts" icon={Terminal} items={scripts.map(named)} />
      <OutputGroup
        title="Packages"
        icon={Package}
        items={packages.map((p) => ({ ...named(p), detail: p.version }))}
      />
      <OutputGroup title="Tasks" icon={ListChecks} items={tasks.map(named)} />
      <OutputGroup
        title="Services"
        icon={Cloud}
        items={services.map((s) => ({
          ...named(s),
          detail: s.proxyEnabled ? "Local proxy" : undefined,
        }))}
      />
      <OutputGroup
        title="Health Checks"
        icon={Heart}
        items={healthchecks.map((h) => ({
          id: h.id,
          title: h.name || h.id,
          description: h.description,
          detail: h.severity || h.type,
        }))}
      />
    </div>
  );
}
