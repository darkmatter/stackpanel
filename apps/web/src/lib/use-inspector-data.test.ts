/**
 * Tests for use-inspector-data hook helpers
 *
 * Exercises script extraction and the contributor filter in the Inspector.
 */

import { describe, expect, it } from "vitest";

import { inspectorContributors } from "./use-inspector-data";

describe("use-inspector-data helpers", () => {
  describe("script extraction logic", () => {
    it("should extract scripts from stackpanel.scripts (top-level)", () => {
      const config = {
        stackpanel: {
          scripts: {
            "my-script": {
              exec: "echo hello",
              description: "A test script",
            },
            "another-script": {
              exec: "npm run build",
              description: "Build the project",
            },
          },
        },
      };

      const scripts = extractScriptsFromConfig(config);
      expect(scripts).toHaveLength(2);
      expect(scripts).toContainEqual({
        name: "my-script",
        command: "echo hello",
        source: "scripts",
      });
      expect(scripts).toContainEqual({
        name: "another-script",
        command: "npm run build",
        source: "scripts",
      });
    });

    it("should extract scripts from stackpanel.scripts", () => {
      const config = {
        stackpanel: {
          scripts: {
            dev: { exec: "npm run dev", description: "Start dev server" },
            build: { exec: "npm run build", description: "Build project" },
          },
        },
      };

      const scripts = extractScriptsFromConfig(config);
      expect(scripts).toHaveLength(2);
      expect(scripts).toContainEqual({
        name: "dev",
        command: "npm run dev",
        source: "scripts",
      });
    });

    it("should handle empty config", () => {
      const scripts = extractScriptsFromConfig(null);
      expect(scripts).toEqual([]);
    });

    it("should handle missing devshell", () => {
      const config = { stackpanel: {} };
      const scripts = extractScriptsFromConfig(config);
      expect(scripts).toEqual([]);
    });

    it("should deduplicate scripts by name", () => {
      const config = {
        stackpanel: {
          scripts: {
            "my-script": { exec: "echo v1" },
          },
          devshell: {
            _scripts: {
              "my-script": { exec: "echo v2" },
            },
          },
        },
      };

      const scripts = extractScriptsFromConfig(config);
      // Should only have one entry (first seen wins)
      const myScripts = scripts.filter((s) => s.name === "my-script");
      expect(myScripts).toHaveLength(1);
    });
  });

  it("lists evaluated module labels and preserves distinct file producers", () => {
    expect(inspectorContributors(
      [{ id: "pg", name: "Database" }, { id: "ui", name: "Studio" }],
      [{ source: "pg" }, { source: "formatter" }, { source: "formatter" }],
    )).toEqual([
      { id: "pg", label: "Database" },
      { id: "formatter", label: "formatter" },
      { id: "ui", label: "Studio" },
    ]);
  });

  describe("config source handling", () => {
    it("should recognize flake_watcher source", () => {
      const source = "flake_watcher";
      expect(normalizeConfigSource(source)).toBe("FlakeWatcher");
    });

    it("should recognize legacy_cache source", () => {
      const source = "legacy_cache";
      expect(normalizeConfigSource(source)).toBe("Cached");
    });

    it("should recognize fresh_eval source", () => {
      const source = "fresh_eval";
      expect(normalizeConfigSource(source)).toBe("Fresh Eval");
    });

    it("should pass through unknown sources", () => {
      const source = "custom_source";
      expect(normalizeConfigSource(source)).toBe("custom_source");
    });

    it("should handle null source", () => {
      expect(normalizeConfigSource(null)).toBe(null);
    });
  });
});

// =============================================================================
// Helper implementations for testing
// These mirror the logic in use-inspector-data.ts
// =============================================================================

interface InspectorScript {
  name: string;
  command: string;
  source: "scripts" | "_scripts" | "_tasks";
}

function extractScriptsFromConfig(
  config: Record<string, unknown> | null
): InspectorScript[] {
  if (!config) return [];

  const scripts: InspectorScript[] = [];
  const seen = new Set<string>();

  const stackpanel = config.stackpanel as Record<string, unknown> | undefined;
  const devshell = (stackpanel?.devshell ?? {}) as Record<string, unknown>;

  // Define sources to check
  // Scripts are now at stackpanel.scripts (top-level), not devshell.commands
  const sources: Array<{
    data: Record<string, unknown> | Array<unknown> | undefined;
    source: InspectorScript["source"];
  }> = [
    {
      data: stackpanel?.scripts as Record<string, unknown> | undefined,
      source: "scripts",
    },
    {
      data: devshell.scripts as Record<string, unknown> | undefined,
      source: "scripts",
    },
    {
      data: devshell._scripts as Record<string, unknown> | undefined,
      source: "_scripts",
    },
    {
      data: devshell._tasks as Array<unknown> | undefined,
      source: "_tasks",
    },
  ];

  for (const { data, source } of sources) {
    if (!data) continue;

    if (Array.isArray(data)) {
      // Commands/tasks format: [{ name, command }]
      for (const item of data) {
        const cmd = item as { name?: string; command?: string };
        if (cmd.name && !seen.has(cmd.name)) {
          seen.add(cmd.name);
          scripts.push({
            name: cmd.name,
            command: cmd.command ?? "",
            source,
          });
        }
      }
    } else {
      // Scripts format: { scriptName: { exec: "..." } }
      for (const [name, value] of Object.entries(data)) {
        if (seen.has(name)) continue;
        seen.add(name);

        let command = "";
        const v = value as { exec?: string } | string;
        if (typeof v === "string") {
          command = v;
        } else if (v?.exec) {
          command = v.exec;
        }

        scripts.push({ name, command, source });
      }
    }
  }

  return scripts;
}

function normalizeConfigSource(source: string | null): string | null {
  if (!source) return null;

  const sourceLabels: Record<string, string> = {
    flake_watcher: "FlakeWatcher",
    legacy_cache: "Cached",
    fresh_eval: "Fresh Eval",
    passthru: "Passthru",
  };

  return sourceLabels[source] ?? source;
}
