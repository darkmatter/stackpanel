// =============================================================================
// Unified module icon mapping — used by panels-panel and app-expanded-content.
// =============================================================================

import {
  Activity,
  Boxes,
  Code,
  Cog,
  FileCode,
  GitBranch,
  Network,
  Rocket,
  SearchCode,
  Server,
  Settings,
  ShieldCheck,
  Zap,
} from "lucide-react";

/**
 * Map module IDs to Lucide icon components.
 * Used by the panels subnav and the app modules tab.
 */
export const MODULE_ICONS: Record<string, React.ElementType> = {
  go: Code,
  bun: Zap,
  caddy: Network,
  healthchecks: Activity,
  "process-compose": Cog,
  turbo: Server,
  oxlint: SearchCode,
  "git-hooks": GitBranch,
  entrypoints: FileCode,
  "app-commands": Code,
};

/**
 * Map lucide icon names (from Nix panel definitions) to components.
 * Used when panels carry an `icon` string instead of a module ID.
 */
const ICON_NAME_MAP: Record<string, React.ElementType> = {
  code: Settings,
  zap: Rocket,
  "search-code": ShieldCheck,
};

/** Resolve an icon for a module by its ID */
export function getModuleIconById(moduleId: string): React.ElementType {
  return MODULE_ICONS[moduleId] ?? Boxes;
}

/** Resolve an icon by its lucide icon name string (from panel metadata) */
export function getModuleIconByName(
  iconName?: string | null,
): React.ElementType {
  if (iconName && ICON_NAME_MAP[iconName]) return ICON_NAME_MAP[iconName];
  return Boxes;
}
