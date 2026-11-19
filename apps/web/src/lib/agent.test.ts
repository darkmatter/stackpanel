/**
 * Unit tests for Agent client utilities
 *
 * These tests focus on parsing logic and helper functions.
 * For full integration tests with a real agent, see:
 *   src/test/integration/agent.integration.test.ts
 */

import { afterEach, describe, expect, it, vi } from "vitest";
import { AgentHttpClient, type TurboPackageGraphResult } from "./agent";

describe("Agent REST credential boundary", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("blocks eager project requests before authentication without touching the network", async () => {
    const request = vi.fn();
    vi.stubGlobal("fetch", request);
    const client = new AgentHttpClient({ requireAuth: true });
    await expect(client.get("/api/project/current")).rejects.toThrow(
      "Agent authentication required",
    );
    expect(request).not.toHaveBeenCalled();
  });

  it("blocks a project write until the provider has pinned a project", async () => {
    const request = vi.fn();
    vi.stubGlobal("fetch", request);
    const client = new AgentHttpClient({ requireAuth: true, token: "paired" });
    await expect(client.nixGenerate()).rejects.toThrow("Select a project first");
    expect(request).not.toHaveBeenCalled();
  });

  it("probes public health without credentials, project headers, or redirects", async () => {
    const request = vi.fn().mockResolvedValue(Response.json({ status: "ok" }));
    vi.stubGlobal("fetch", request);
    const client = new AgentHttpClient({ token: "private", projectId: "project" });
    await client.health();
    expect(request).toHaveBeenCalledTimes(1);
    expect(request).toHaveBeenCalledWith("http://localhost:9876/health", {
      credentials: "omit",
      redirect: "error",
    });
  });

  it("does not send a mutation after the paired agent is replaced on the same port", async () => {
    const claims = btoa(
      JSON.stringify({ agent_id: "paired", exp: Date.now() / 1000 + 60 }),
    ).replace(/=+$/, "");
    const request = vi
      .fn()
      .mockResolvedValue(Response.json({ status: "ok", agent_id: "replacement" }));
    vi.stubGlobal("fetch", request);
    const client = new AgentHttpClient({
      token: `header.${claims}.signature`,
      projectId: "project",
    });
    await expect(client.post("/api/project/open", { path: "/repo" })).rejects.toThrow();
    expect(request).toHaveBeenCalledTimes(1);
    for (const [url, init] of request.mock.calls) {
      expect(String(url)).toBe("http://localhost:9876/health");
      expect(new Headers(init?.headers).has("X-Stackpanel-Token")).toBe(false);
    }
  });
});

describe("Agent client utilities", () => {
  describe("TurboPackageGraphResult parsing", () => {
    it("should correctly structure package graph query results with tasks", () => {
      const mockResponse = {
        data: {
          packageGraph: {
            nodes: {
              items: [
                {
                  name: "//",
                  path: ".",
                  tasks: { items: [{ name: "build" }] },
                },
                {
                  name: "@stackpanel/api",
                  path: "packages/api",
                  tasks: {
                    items: [{ name: "build" }, { name: "test" }, { name: "dev" }],
                  },
                },
                {
                  name: "@stackpanel/auth",
                  path: "packages/auth",
                  tasks: { items: [{ name: "build" }, { name: "test" }] },
                },
                {
                  name: "web",
                  path: "apps/web",
                  tasks: {
                    items: [{ name: "build" }, { name: "dev" }, { name: "lint" }],
                  },
                },
              ],
            },
          },
        },
      };

      // Extract packages with tasks (same logic as getPackageGraph)
      const packages = mockResponse.data.packageGraph.nodes.items.map((item) => ({
        name: item.name,
        path: item.path,
        tasks: item.tasks.items.map((t) => ({ name: t.name })),
      }));

      expect(packages).toHaveLength(4);
      expect(packages[0]).toEqual({
        name: "//",
        path: ".",
        tasks: [{ name: "build" }],
      });
      expect(packages[1].tasks).toHaveLength(3);
      expect(packages[3].name).toBe("web");
      expect(packages[3].tasks).toContainEqual({ name: "dev" });
    });

    it("should extract package names only", () => {
      const mockResponse = {
        data: {
          packageGraph: {
            nodes: {
              items: [
                { name: "//", path: ".", tasks: { items: [] } },
                {
                  name: "@stackpanel/api",
                  path: "packages/api",
                  tasks: { items: [] },
                },
                { name: "web", path: "apps/web", tasks: { items: [] } },
              ],
            },
          },
        },
      };

      // Extract package names (same logic as getPackages)
      const packages = mockResponse.data.packageGraph.nodes.items.map((item) => item.name);

      expect(packages).toEqual(["//", "@stackpanel/api", "web"]);
    });

    it("should filter out root package when excludeRoot is true", () => {
      const mockResponse = {
        data: {
          packageGraph: {
            nodes: {
              items: [
                { name: "//", path: ".", tasks: { items: [] } },
                {
                  name: "@stackpanel/api",
                  path: "packages/api",
                  tasks: { items: [] },
                },
                { name: "web", path: "apps/web", tasks: { items: [] } },
              ],
            },
          },
        },
      };

      // Same logic as getPackages with excludeRoot
      let packages = mockResponse.data.packageGraph.nodes.items.map((item) => item.name);
      packages = packages.filter((name) => name !== "//");

      expect(packages).toEqual(["@stackpanel/api", "web"]);
      expect(packages).not.toContain("//");
    });

    it("should filter out root package from full package graph", () => {
      const mockResponse = {
        data: {
          packageGraph: {
            nodes: {
              items: [
                {
                  name: "//",
                  path: ".",
                  tasks: { items: [{ name: "build" }] },
                },
                {
                  name: "web",
                  path: "apps/web",
                  tasks: { items: [{ name: "dev" }] },
                },
              ],
            },
          },
        },
      };

      // Same logic as getPackageGraph with excludeRoot
      let packages = mockResponse.data.packageGraph.nodes.items.map((item) => ({
        name: item.name,
        path: item.path,
        tasks: item.tasks.items.map((t) => ({ name: t.name })),
      }));
      packages = packages.filter((pkg) => pkg.name !== "//");

      expect(packages).toHaveLength(1);
      expect(packages[0].name).toBe("web");
    });

    it("should handle empty package list", () => {
      const mockResponse: TurboPackageGraphResult = {
        data: {
          packageGraph: {
            nodes: {
              items: [],
            },
          },
        },
      };

      const packages = mockResponse.data.packageGraph.nodes.items.map((item) => item.name);

      expect(packages).toEqual([]);
    });

    it("should handle packages with no tasks", () => {
      const mockResponse: TurboPackageGraphResult = {
        data: {
          packageGraph: {
            nodes: {
              items: [
                {
                  name: "empty-pkg",
                  path: "packages/empty",
                  tasks: { items: [] },
                },
              ],
            },
          },
        },
      };

      const packages = mockResponse.data.packageGraph.nodes.items.map((item) => ({
        name: item.name,
        path: item.path,
        tasks: item.tasks.items.map((t) => ({ name: t.name })),
      }));

      expect(packages[0].tasks).toEqual([]);
    });

    it("should collect all unique tasks across packages", () => {
      const mockResponse = {
        data: {
          packageGraph: {
            nodes: {
              items: [
                {
                  name: "pkg-a",
                  path: "a",
                  tasks: { items: [{ name: "build" }, { name: "test" }] },
                },
                {
                  name: "pkg-b",
                  path: "b",
                  tasks: { items: [{ name: "build" }, { name: "dev" }] },
                },
                {
                  name: "pkg-c",
                  path: "c",
                  tasks: { items: [{ name: "lint" }, { name: "test" }] },
                },
              ],
            },
          },
        },
      };

      // Collect all unique task names
      const taskSet = new Set<string>();
      for (const item of mockResponse.data.packageGraph.nodes.items) {
        for (const task of item.tasks.items) {
          taskSet.add(task.name);
        }
      }
      const allTasks = Array.from(taskSet).sort();

      expect(allTasks).toEqual(["build", "dev", "lint", "test"]);
    });
  });

  describe("turboQuery response parsing", () => {
    it("should parse valid JSON stdout with packageGraph", () => {
      const stdout =
        '{"data":{"packageGraph":{"nodes":{"items":[{"name":"//","path":".","tasks":{"items":[]}}]}}}}';

      const parsed = JSON.parse(stdout);

      expect(parsed).toHaveProperty("data");
      expect(parsed.data.packageGraph.nodes.items).toHaveLength(1);
    });

    it("should throw on invalid JSON", () => {
      const stdout = "not valid json";

      expect(() => JSON.parse(stdout)).toThrow();
    });

    it("should detect failed commands by exit code", () => {
      const mockExecResult = {
        exit_code: 1,
        stdout: "",
        stderr: "turbo: command not found",
      };

      // Same logic as turboQuery error handling
      const shouldThrow = mockExecResult.exit_code !== 0;

      expect(shouldThrow).toBe(true);
    });
  });

  describe("ExecResult structure", () => {
    it("should have expected fields for successful execution", () => {
      const result = {
        exit_code: 0,
        stdout: "hello world\n",
        stderr: "",
      };

      expect(result.exit_code).toBe(0);
      expect(result.stdout.trim()).toBe("hello world");
      expect(result.stderr).toBe("");
    });

    it("should capture stderr separately", () => {
      const result = {
        exit_code: 0,
        stdout: "output\n",
        stderr: "warning: something\n",
      };

      expect(result.stdout).toContain("output");
      expect(result.stderr).toContain("warning");
    });
  });
});
