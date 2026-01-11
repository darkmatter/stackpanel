/**
 * Integration tests for the Agent client
 *
 * These tests use real stackpanel projects created from templates
 * and run actual agent servers to test the full integration.
 *
 * Run with: bun run test:integration
 * Debug with: DEBUG_AGENT=1 bun run test:integration
 */

import { describe, it, expect, afterAll } from "vitest";
import { createSharedTestProject, withTestProject } from "./test-project";

// Skip integration tests in CI unless explicitly enabled
const SKIP_INTEGRATION =
  process.env.CI === "true" && !process.env.RUN_INTEGRATION_TESTS;

describe.skipIf(SKIP_INTEGRATION)("Agent Integration Tests", () => {
  // Use a shared project for most tests to improve performance
  const sharedProject = createSharedTestProject({
    template: "minimal",
    keepOnCleanup: !!process.env.KEEP_TEST_PROJECTS,
  });

  afterAll(async () => {
    await sharedProject.cleanup();
  });

  describe("health check", () => {
    it("should report healthy status", async () => {
      const project = await sharedProject.get();
      const health = await project.client.ping();

      expect(health).not.toBeNull();
      expect(health?.status).toBe("ok");
    });

    it("should report project root", async () => {
      const project = await sharedProject.get();
      const health = await project.client.ping();

      expect(health?.project_root).toBe(project.projectDir);
      expect(health?.has_project).toBe(true);
    });
  });

  describe("exec", () => {
    it("should execute simple commands", async () => {
      const project = await sharedProject.get();
      const result = await project.client.exec({
        command: "echo",
        args: ["hello", "world"],
      });

      expect(result.exit_code).toBe(0);
      expect(result.stdout.trim()).toBe("hello world");
      expect(result.stderr).toBe("");
    });

    it("should capture stderr", async () => {
      const project = await sharedProject.get();
      const result = await project.client.exec({
        command: "sh",
        args: ["-c", "echo error >&2"],
      });

      expect(result.exit_code).toBe(0);
      expect(result.stderr.trim()).toBe("error");
    });

    it("should report non-zero exit codes", async () => {
      const project = await sharedProject.get();
      const result = await project.client.exec({
        command: "sh",
        args: ["-c", "exit 42"],
      });

      expect(result.exit_code).toBe(42);
    });
  });

  describe("turboQuery", () => {
    it("should execute turbo query and return packages", async () => {
      const project = await sharedProject.get();
      const result = await project.client.turboQuery<{
        data: { packages: { items: Array<{ name: string }> } };
      }>("query { packages { items { name } } }");

      expect(result).toHaveProperty("data");
      expect(result.data).toHaveProperty("packages");
      expect(result.data.packages).toHaveProperty("items");
      expect(Array.isArray(result.data.packages.items)).toBe(true);
    });

    it("should throw on invalid query", async () => {
      const project = await sharedProject.get();

      await expect(
        project.client.turboQuery("invalid query syntax {{{"),
      ).rejects.toThrow();
    });
  });

  describe("getPackages", () => {
    it("should return all packages including root", async () => {
      const project = await sharedProject.get();
      const packages = await project.client.getPackages();

      expect(Array.isArray(packages)).toBe(true);
      // Root package is always present
      expect(packages).toContain("//");
    });

    it("should filter out root when excludeRoot is true", async () => {
      const project = await sharedProject.get();
      const packages = await project.client.getPackages({ excludeRoot: true });

      expect(Array.isArray(packages)).toBe(true);
      expect(packages).not.toContain("//");
    });
  });

  describe("file operations", () => {
    it("should read existing files", async () => {
      const project = await sharedProject.get();
      const content = await project.client.readFile("flake.nix");

      expect(content.exists).toBe(true);
      expect(content.path).toBe("flake.nix");
      expect(content.content).toContain("description");
    });

    it("should report non-existent files", async () => {
      const project = await sharedProject.get();
      const content = await project.client.readFile("nonexistent-file.txt");

      expect(content.exists).toBe(false);
    });

    it("should write and read back files", async () => {
      const project = await sharedProject.get();
      const testContent = `Test file created at ${Date.now()}`;

      await project.client.writeFile("test-write.txt", testContent);
      const readBack = await project.client.readFile("test-write.txt");

      expect(readBack.exists).toBe(true);
      expect(readBack.content).toBe(testContent);
    });
  });

  describe("nix eval", () => {
    it("should evaluate simple expressions", async () => {
      const project = await sharedProject.get();
      const result = await project.client.nixEval<number>("1 + 1");

      expect(result).toBe(2);
    });

    it("should evaluate complex expressions", async () => {
      const project = await sharedProject.get();
      const result = await project.client.nixEval<{ a: number; b: string }>(
        '{ a = 42; b = "hello"; }',
      );

      expect(result).toEqual({ a: 42, b: "hello" });
    });

    it("should evaluate builtins", async () => {
      const project = await sharedProject.get();
      const result = await project.client.nixEval<number>(
        "builtins.length [1 2 3]",
      );

      expect(result).toBe(3);
    });
  });
});

// Test with different templates
describe.skipIf(SKIP_INTEGRATION)("Template Variants", () => {
  it("should work with the default template", async () => {
    await withTestProject({ template: "default" }, async (project) => {
      const health = await project.client.ping();
      expect(health).not.toBeNull();
    });
  });

  it("should work with the native template", async () => {
    await withTestProject({ template: "native" }, async (project) => {
      const health = await project.client.ping();
      expect(health).not.toBeNull();
    });
  });
});
