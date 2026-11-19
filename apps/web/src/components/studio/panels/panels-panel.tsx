import { PanelHeader } from "./shared/panel-header";
import { StudioPanel } from "./shared/studio-panel";
import { studioPanelKey, useStudioPanels } from "./shared/use-studio-panels";

export function PanelsPanel({ moduleId }: { moduleId?: string }) {
  const { modules, panels, isLoading, error } = useStudioPanels();
  const modulePanels = panels.filter((panel) => panel.slot === "module");
  const selectedId = moduleId ?? modulePanels[0]?.module;
  const selected = selectedId ? modules.get(selectedId) : undefined;
  const visible = modulePanels.filter((panel) => panel.module === selectedId);

  return (
    <section className="space-y-4">
      <PanelHeader
        title={selected?.name || "Panels"}
        description={selected?.description || "Module status and configuration panels"}
      />
      {error ? (
        <p role="alert">Could not load panels: {error.message}</p>
      ) : isLoading ? (
        <p role="status">Loading panels…</p>
      ) : visible.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {moduleId ? `No module panels for ${moduleId}.` : "No enabled module panels."}
        </p>
      ) : (
        visible.map((panel) => <StudioPanel key={studioPanelKey(panel)} panel={panel} />)
      )}
    </section>
  );
}
