import type { RegistryModule } from "@stackpanel/proto/agent/v1/module";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Package, RefreshCw } from "lucide-react";
import { useState } from "react";
import { getModuleIconByName } from "../shared/module-icons";
import { RegistryModuleDrawer } from "./registry-module-drawer";
import { getCategoryLabel } from "./module-labels";
import { useRegistryModules } from "./use-modules";

function RegistryCard({ module, onSelect }: { module: RegistryModule; onSelect: () => void }) {
  const Icon = getModuleIconByName(module.icon);
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-3">
          <Icon className="h-5 w-5 shrink-0 text-muted-foreground" />
          <CardTitle className="min-w-0 truncate text-base">{module.name}</CardTitle>
          {module.installed && (
            <Badge variant="outline">
              Installed{module.installedVersion && ` · ${module.installedVersion}`}
            </Badge>
          )}
        </div>
        <p className="text-sm text-muted-foreground">{module.description}</p>
      </CardHeader>
      <CardContent className="space-y-3">
        <p className="text-sm">
          {getCategoryLabel(module.category)}
          {module.latestVersion && ` · Latest ${module.latestVersion}`}
        </p>
        <div className="flex flex-wrap gap-1">
          {module.tags.map((tag) => (
            <Badge key={tag} variant="secondary">
              {tag}
            </Badge>
          ))}
        </div>
        <Button variant="outline" size="sm" onClick={onSelect}>
          View Details
        </Button>
      </CardContent>
    </Card>
  );
}

export function RegistryBrowser() {
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("");
  const [tag, setTag] = useState("");
  const [moduleId, setModuleId] = useState<string | null>(null);
  const { data, error, isFetching, refetch } = useRegistryModules({
    search: search.trim(),
    category: category.trim(),
    tag: tag.trim(),
  });
  const hasFilter = !!(search || category || tag);
  return (
    <section className="space-y-6" aria-label="Module registry">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold">Module Registry</h3>
          <p className="text-sm text-muted-foreground">
            Find modules in your configured registries.
          </p>
        </div>
        <Button variant="outline" size="sm" disabled={isFetching} onClick={() => void refetch()}>
          <RefreshCw className="mr-2 h-4 w-4" />
          Refresh
        </Button>
      </div>
      <div className="flex flex-col gap-2 sm:flex-row">
        <Input
          aria-label="Search modules"
          placeholder="Search modules..."
          value={search}
          onChange={(event) => setSearch(event.target.value)}
        />
        <Input
          className="sm:max-w-40"
          aria-label="Filter by category"
          placeholder="Category"
          value={category}
          onChange={(event) => setCategory(event.target.value)}
        />
        <Input
          className="sm:max-w-40"
          aria-label="Filter by tag"
          placeholder="Tag"
          value={tag}
          onChange={(event) => setTag(event.target.value)}
        />
      </div>
      {error ? (
        <div className="space-y-2">
          <p role="alert" className="text-sm text-destructive">
            Failed to load registry: {error.message}
          </p>
          <Button variant="outline" onClick={() => void refetch()}>
            Try again
          </Button>
        </div>
      ) : !data ? (
        <p role="status">Loading registry…</p>
      ) : data.modules.length === 0 ? (
        <div className="flex flex-col items-center gap-2 py-16 text-muted-foreground">
          <Package className="size-8" />
          <p>{hasFilter ? "No matching modules" : "No modules available"}</p>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {data.modules.map((module) => (
            <RegistryCard
              key={module.id}
              module={module}
              onSelect={() => setModuleId(module.slug)}
            />
          ))}
        </div>
      )}
      {moduleId && (
        <RegistryModuleDrawer
          moduleId={moduleId}
          open
          onOpenChange={(open) => {
            if (!open) setModuleId(null);
          }}
        />
      )}
    </section>
  );
}
