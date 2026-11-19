import { getModuleIconByName } from "../shared/module-icons";
import type { NixPanel } from "../shared/panel-types";
import { studioPanelKey } from "../shared/use-studio-panels";

export function getSetupPanelSteps(panels: readonly NixPanel[]) {
  return panels
    .filter((panel) => panel.enabled && panel.slot === "setup")
    .map((panel) => ({
      id: studioPanelKey(panel),
      label: panel.nav?.label ?? panel.title,
      icon: getModuleIconByName(panel.nav?.icon ?? panel.icon),
      description: panel.description ?? "",
      panel,
    }));
}
