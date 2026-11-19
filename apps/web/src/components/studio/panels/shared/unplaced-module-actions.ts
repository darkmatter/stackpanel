import type { NixPanel } from "./panel-types";
import { parsePanelSpec } from "./spec/catalog";

/** Keep the default toolbar useful without presenting the same action twice. A broken
 * layout never hides the owner's working native controls. Call with one owner's panels. */
export function unplacedModuleActions(ids: readonly string[], panels: readonly NixPanel[]) {
  const remaining = new Set(ids);
  for (const panel of panels) {
    if (panel.type === "PANEL_TYPE_SPEC" || panel.spec != null) {
      if (panel.type !== "PANEL_TYPE_SPEC" || panel.uiBundle) continue;
      const parsed = parsePanelSpec(panel.spec);
      if (!parsed.ok) continue;
      if (parsed.actionIds === "all") return [];
      for (const id of parsed.actionIds) remaining.delete(id);
    } else {
      for (const id of panel.actions ?? []) remaining.delete(id);
      for (const id of panel.rowActions ?? []) remaining.delete(id);
      if (panel.dataAction) remaining.delete(panel.dataAction);
    }
  }
  return [...remaining];
}
