/**
 * Variable type configuration and helper functions
 */

import { Key, Server, Settings, Sparkles } from "lucide-react";

export const VARIABLE_TYPES = [
  {
    value: "secret",
    label: "Secret",
    description: "Sensitive value stored encrypted",
    icon: Key,
    color: "bg-red-500/20 text-red-400",
  },
  {
    value: "config",
    label: "Config",
    description: "Non-sensitive configuration",
    icon: Settings,
    color: "bg-blue-500/20 text-blue-400",
  },
  {
    value: "computed",
    label: "Computed",
    description: "Derived from other config",
    icon: Sparkles,
    color: "bg-purple-500/20 text-purple-400",
  },
  {
    value: "service",
    label: "Service",
    description: "Auto-generated from service",
    icon: Server,
    color: "bg-green-500/20 text-green-400",
  },
] as const;

export type VariableTypeName = (typeof VARIABLE_TYPES)[number]["value"];

export function getTypeConfig(type: string) {
  return VARIABLE_TYPES.find((t) => t.value === type) ?? VARIABLE_TYPES[1];
}
