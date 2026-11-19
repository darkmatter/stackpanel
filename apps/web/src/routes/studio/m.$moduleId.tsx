import { createFileRoute, Link } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { useState } from "react";
import { ModuleDetailDrawer } from "@/components/studio/panels/modules/module-detail-drawer";
import { ModuleMarkdown } from "@/components/studio/panels/shared/module-markdown";
import { PanelActionBar } from "@/components/studio/panels/shared/panel-action-bar";
import { PanelHeader } from "@/components/studio/panels/shared/panel-header";
import { StudioPanel } from "@/components/studio/panels/shared/studio-panel";
import { unplacedModuleActions } from "@/components/studio/panels/shared/unplaced-module-actions";
import {
  studioPanelKey,
  useStudioPanels,
} from "@/components/studio/panels/shared/use-studio-panels";

export const Route = createFileRoute("/studio/m/$moduleId")({ component: ModulePage });

function ModulePage() {
  const { moduleId } = Route.useParams();
  const { modules, panels, catalog, isLoading, error } = useStudioPanels();
  const [detailsOpen, setDetailsOpen] = useState(false);
  if (error) return <p role="alert">Could not load module: {error.message}</p>;
  if (isLoading) return <p role="status">Loading module…</p>;

  const module = modules.get(moduleId);
  if (!module) {
    return (
      <p>
        No enabled module named {moduleId}.{" "}
        <Link className="underline" to="/studio/modules">
          Explore modules
        </Link>
      </p>
    );
  }
  // `module dev` opens this route even for a module which contributes no
  // sidebar item. Use its other panels and README as the author landing page.
  const owned = panels.filter((panel) => panel.module === moduleId);
  const sidebar = owned.filter((panel) => panel.slot === "sidebar");
  const pagePanels = sidebar.length ? sidebar : owned;
  const otherActions = unplacedModuleActions(
    module.actionIds,
    catalog.filter((p) => p.module === moduleId && (!sidebar.length || p.slot === "sidebar")),
  );

  return (
    <section className="space-y-6">
      <PanelHeader
        title={module.name}
        description={module.description ?? undefined}
        actions={
          <div className="flex flex-wrap gap-2">
            {otherActions.length > 0 && (
              <PanelActionBar moduleId={moduleId} actionIds={otherActions} />
            )}
            <Button variant="outline" size="sm" onClick={() => setDetailsOpen(true)}>
              Module details
            </Button>
          </div>
        }
      />
      {detailsOpen && <ModuleDetailDrawer moduleId={moduleId} open onOpenChange={setDetailsOpen} />}
      {pagePanels.map((panel) => (
        <div key={studioPanelKey(panel)} id={panel.id} className="scroll-mt-4">
          <StudioPanel panel={panel} />
        </div>
      ))}
      {module.readme && (
        <details>
          <summary className="cursor-pointer text-sm font-medium">Module documentation</summary>
          <ModuleMarkdown>{module.readme}</ModuleMarkdown>
        </details>
      )}
    </section>
  );
}
