/**
 * Command category configuration and helper functions
 */

export const COMMAND_CATEGORIES = [
  { value: "development", label: "Development", color: "bg-blue-500/20 text-blue-400" },
  { value: "build", label: "Build", color: "bg-orange-500/20 text-orange-400" },
  { value: "testing", label: "Testing", color: "bg-green-500/20 text-green-400" },
  { value: "quality", label: "Quality", color: "bg-purple-500/20 text-purple-400" },
  { value: "database", label: "Database", color: "bg-cyan-500/20 text-cyan-400" },
  { value: "deployment", label: "Deployment", color: "bg-red-500/20 text-red-400" },
  { value: "codegen", label: "Code Generation", color: "bg-yellow-500/20 text-yellow-400" },
  { value: "production", label: "Production", color: "bg-pink-500/20 text-pink-400" },
  { value: "other", label: "Other", color: "bg-gray-500/20 text-gray-400" },
] as const;

export type CommandCategory = (typeof COMMAND_CATEGORIES)[number]["value"];

export function getCategoryColor(category: string): string {
  return (
    COMMAND_CATEGORIES.find((c) => c.value === category)?.color ??
    "bg-gray-500/20 text-gray-400"
  );
}

export function getCategoryLabel(category: string): string {
  return COMMAND_CATEGORIES.find((c) => c.value === category)?.label ?? category;
}
