/**
 * Configuration sections definition for sidebar navigation.
 * Each section represents a collapsible form panel in the configuration page.
 */

import type { LucideIcon } from "lucide-react";
import {
  Github,
  Lock,
  Settings,
  Shield,
  Terminal,
} from "lucide-react";

export interface ConfigurationSection {
  id: string;
  label: string;
  icon: LucideIcon;
  description: string;
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

/**
 * Get a section by its ID
 */
export function getConfigurationSection(id: string): ConfigurationSection | undefined {
  return CONFIGURATION_SECTIONS.find((section) => section.id === id);
}

/**
 * Get the default section ID (first in the list)
 */
export function getDefaultSectionId(): ConfigurationSectionId {
  return CONFIGURATION_SECTIONS[0].id;
}
