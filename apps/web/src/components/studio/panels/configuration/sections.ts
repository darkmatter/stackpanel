/**
 * Configuration sections definition for sidebar navigation.
 * Each section represents a collapsible form panel in the configuration page.
 */

import type { ElementType } from "react";
import { getModuleIconByName } from "../shared/module-icons";
import type { NixPanel } from "../shared/panel-types";
import { studioPanelKey } from "../shared/use-studio-panels";
import { GitBranch as Github, Lock, Settings, Shield, Terminal } from "lucide-react";

export interface ConfigurationSection {
  id: string;
  label: string;
  icon: ElementType;
  description: string;
  panel?: NixPanel;
}

export const CONFIGURATION_SECTIONS: ConfigurationSection[] = [
  {
    id: "github",
    label: "GitHub",
    icon: Github,
    description: "Repository and user sync settings",
  },
  {
    id: "step-ca",
    label: "Step CA",
    icon: Shield,
    description: "Local TLS certificate authority",
  },
  {
    id: "aws",
    label: "AWS Roles Anywhere",
    icon: Lock,
    description: "Certificate-based AWS authentication",
  },
  {
    id: "starship",
    label: "Starship Prompt",
    icon: Terminal,
    description: "Shell prompt theme settings",
  },
  {
    id: "ide",
    label: "IDE Integration",
    icon: Settings,
    description: "VS Code, Zed, and other IDE workspace configuration",
  },
  {
    id: "cache",
    label: "Binary Cache",
    icon: Shield,
    description: "Cachix build caching",
  },
] as const;

export type ConfigurationSectionId = (typeof CONFIGURATION_SECTIONS)[number]["id"];

/** The sidebar and the content area must resolve exactly the same section IDs. */
export function getConfigurationSections(panels: readonly NixPanel[]): ConfigurationSection[] {
  return [
    ...CONFIGURATION_SECTIONS,
    ...panels
      .filter((panel) => panel.enabled && panel.slot === "configuration")
      .map((panel) => ({
        id: studioPanelKey(panel),
        label: panel.nav?.label ?? panel.title,
        icon: getModuleIconByName(panel.nav?.icon ?? panel.icon),
        description: panel.description ?? "",
        panel,
      })),
  ];
}

/**
 * Get the default section ID (first in the list)
 */
export function getDefaultSectionId(): ConfigurationSectionId {
  return CONFIGURATION_SECTIONS[0].id;
}
