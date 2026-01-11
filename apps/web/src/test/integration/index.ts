/**
 * Integration test utilities
 *
 * This module provides helpers for running integration tests with real
 * stackpanel projects and agent servers.
 *
 * @example
 * import { TestProject, withTestProject, createSharedTestProject } from "@/test/integration";
 *
 * // One-off test
 * await withTestProject({ template: "minimal" }, async (project) => {
 *   const packages = await project.client.getPackages();
 *   expect(packages).toContain("//");
 * });
 *
 * // Shared project for a test suite
 * describe("my tests", () => {
 *   const projectRef = createSharedTestProject({ template: "minimal" });
 *   afterAll(() => projectRef.cleanup());
 *
 *   it("works", async () => {
 *     const project = await projectRef.get();
 *     // ...
 *   });
 * });
 */

export {
  TestProject,
  withTestProject,
  createSharedTestProject,
  type TestProjectOptions,
  type TemplateName,
} from "./test-project";
