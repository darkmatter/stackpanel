import { PanelRenderer } from "./panel-renderers";
import type { NixPanel } from "./panel-types";
import { studioPanelMatchesApp, useStudioPanels } from "./use-studio-panels";

export function StudioPanel({ panel, appId }: { panel: NixPanel; appId?: string }) {
  const { catalog } = useStudioPanels();
  if (!catalog.includes(panel) || (appId && !studioPanelMatchesApp(panel, appId))) return null;
  return <PanelRenderer panel={panel} panels={catalog} appId={appId} />;
}
