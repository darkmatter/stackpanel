// =============================================================================
// Shared module utility functions.
// =============================================================================

/** Well-known module display names */
const KNOWN_NAMES: Record<string, string> = {
  go: "Go",
  bun: "Bun",
  oxlint: "OxLint",
  turbo: "Turbo",
  caddy: "Caddy",
  "process-compose": "Processes",
  "git-hooks": "Git Hooks",
  healthchecks: "Healthchecks",
  entrypoints: "Entrypoints",
  "app-commands": "Commands",
};

/**
 * Convert a module ID to a human-readable name.
 * Uses a known-names map first, then falls back to title-casing.
 *
 * "go" → "Go", "git-hooks" → "Git Hooks", "my-mod" → "My Mod"
 */
export function formatModuleName(id: string): string {
  if (KNOWN_NAMES[id]) return KNOWN_NAMES[id];
  return id
    .split("-")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}
