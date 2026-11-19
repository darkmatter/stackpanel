/**
 * TestProject - Integration test helper for real agent testing
 *
 * This module provides utilities for setting up real stackpanel projects
 * from templates and running an actual agent server for integration tests.
 *
 * Usage:
 *   const project = await TestProject.create({ template: "minimal" });
 *   const client = project.getClient();
 *   // ... run tests ...
 *   await project.cleanup();
 *
 * Or with the helper:
 *   await withTestProject({ template: "minimal" }, async (project) => {
 *     const packages = await project.client.getPackages();
 *     expect(packages).toContain("//");
 *   });
 */

import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { access, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AgentHttpClient } from "../../lib/agent";

/** Available stackpanel templates */
export type TemplateName = "default" | "minimal";

/** Options for creating a test project */
export interface TestProjectOptions {
  /** Template to initialize from (default: "minimal") */
  template?: TemplateName;
  /** Custom port for the agent (default: auto-assigned starting from 19876) */
  port?: number;
  /** Keep the project directory after cleanup (for debugging) */
  keepOnCleanup?: boolean;
  /** Timeout for agent startup in milliseconds (default: 60000) */
  startupTimeout?: number;
  /** Path to stackpanel repo root (auto-detected if not provided) */
  repoRoot?: string;
}

/** Port counter for auto-assigning unique ports */
let nextPort = 19876;

/**
 * Get the stackpanel repo root by looking for known markers
 */
async function findRepoRoot(): Promise<string> {
  // In test environment, we can use process.cwd() or environment variable
  const envRoot = process.env.STACKPANEL_REPO_ROOT;
  if (envRoot) {
    return envRoot;
  }

  // Try to find it relative to this file's location
  // This file is at: apps/web/src/test/integration/test-project.ts
  // Repo root is 5 levels up
  const currentDir = new URL(".", import.meta.url).pathname;
  const repoRoot = join(currentDir, "..", "..", "..", "..", "..");

  return repoRoot;
}

/**
 * Wait for a condition to be true, polling at intervals
 */
async function waitFor(
  condition: () => Promise<boolean>,
  options: { timeout: number; interval?: number; message?: string },
): Promise<void> {
  const { timeout, interval = 500, message = "Condition not met" } = options;
  const start = Date.now();

  while (Date.now() - start < timeout) {
    if (await condition()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, interval));
  }

  throw new Error(`Timeout: ${message} (waited ${timeout}ms)`);
}

/**
 * TestProject represents a temporary stackpanel project with a running agent
 */
export class TestProject {
  /** Path to the temporary project directory */
  readonly projectDir: string;
  /** Port the agent is running on */
  readonly port: number;
  /** The HTTP client connected to the agent */
  readonly client: AgentHttpClient;
  /** The auth token for the agent */
  readonly token: string;

  private agentProcess: ChildProcess | null = null;
  private keepOnCleanup: boolean;
  private cleanedUp = false;

  private constructor(projectDir: string, port: number, token: string, keepOnCleanup: boolean) {
    this.projectDir = projectDir;
    this.port = port;
    this.token = token;
    this.keepOnCleanup = keepOnCleanup;
    this.client = new AgentHttpClient("localhost", port, token);
  }

  /**
   * Create a new test project from a template
   */
  static async create(options: TestProjectOptions = {}): Promise<TestProject> {
    const {
      template = "minimal",
      port = nextPort++,
      keepOnCleanup = false,
      startupTimeout = 60000,
      repoRoot: providedRepoRoot,
    } = options;

    const repoRoot = providedRepoRoot ?? (await findRepoRoot());

    // Create temporary directory
    const tempBase = join(tmpdir(), "stackpanel-test-");
    const projectDir = await mkdtemp(tempBase);

    console.log(`[TestProject] Creating test project at ${projectDir}`);
    console.log(`[TestProject] Using template: ${template}`);
    console.log(`[TestProject] Agent port: ${port}`);

    try {
      // Initialize from template using nix flake init
      await TestProject.initFromTemplate(projectDir, template, repoRoot);

      const goDir = join(repoRoot, "apps", "stackpanel-go");
      const binary = join(goDir, "result", "bin", "stackpanel");
      const built = await access(binary).then(
        () => true,
        () => false,
      );
      const command = built ? binary : "go";
      const prefix = built ? [] : ["run", "."];
      const cwd = built ? projectDir : goDir;
      const env = {
        ...process.env,
        STACKPANEL_TEST_PAIRING_TOKEN: randomBytes(32).toString("hex"),
        STACKPANEL_PROJECT_ROOT: projectDir,
      };
      // This Node client has no browser Origin; the JWT is still agent-specific.
      const stdout = execFileSync(command, [...prefix, "agent", "test-token", "--json"], {
        cwd,
        env,
        encoding: "utf8",
      });
      const { token, agent_id: agentId } = JSON.parse(stdout);
      if (typeof token !== "string" || !token || typeof agentId !== "string" || !agentId) {
        throw new Error("Agent test-token returned no pairing identity");
      }

      // Start the agent
      const project = new TestProject(projectDir, port, token, keepOnCleanup);
      await project.startAgent(command, prefix, cwd, env, agentId, startupTimeout);

      return project;
    } catch (error) {
      // Clean up on failure
      if (!keepOnCleanup) {
        await rm(projectDir, { recursive: true, force: true }).catch(() => {});
      }
      throw error;
    }
  }

  /**
   * Initialize a directory from a stackpanel template
   */
  private static async initFromTemplate(
    projectDir: string,
    template: TemplateName,
    repoRoot: string,
  ): Promise<void> {
    // Use nix flake init with the local repo as the template source
    const flakeRef = `${repoRoot}#${template}`;

    console.log(`[TestProject] Running: nix flake init -t ${flakeRef}`);

    await new Promise<void>((resolve, reject) => {
      const proc = spawn("nix", ["flake", "init", "-t", flakeRef], {
        cwd: projectDir,
        stdio: ["ignore", "pipe", "pipe"],
      });

      let stdout = "";
      let stderr = "";

      proc.stdout?.on("data", (data) => {
        stdout += data.toString();
      });

      proc.stderr?.on("data", (data) => {
        stderr += data.toString();
      });

      proc.on("close", (code) => {
        if (code === 0) {
          console.log(`[TestProject] Template initialized successfully`);
          resolve();
        } else {
          reject(
            new Error(
              `nix flake init failed with code ${code}\nstdout: ${stdout}\nstderr: ${stderr}`,
            ),
          );
        }
      });

      proc.on("error", reject);
    });

    // Initialize git repo (required for flakes)
    await new Promise<void>((resolve, reject) => {
      const proc = spawn("git", ["init"], {
        cwd: projectDir,
        stdio: "ignore",
      });
      proc.on("close", (code) => {
        if (code === 0) resolve();
        else reject(new Error(`git init failed with code ${code}`));
      });
      proc.on("error", reject);
    });

    // Stage all files (required for flakes to see them)
    await new Promise<void>((resolve, reject) => {
      const proc = spawn("git", ["add", "-A"], {
        cwd: projectDir,
        stdio: "ignore",
      });
      proc.on("close", (code) => {
        if (code === 0) resolve();
        else reject(new Error(`git add failed with code ${code}`));
      });
      proc.on("error", reject);
    });
  }

  /**
   * Start the stackpanel agent for this project
   */
  private async startAgent(
    command: string,
    prefix: string[],
    cwd: string,
    env: NodeJS.ProcessEnv,
    agentId: string,
    timeout: number,
  ): Promise<void> {
    const args = [
      ...prefix,
      "agent",
      "--port",
      String(this.port),
      "--project-root",
      this.projectDir,
    ];
    this.agentProcess = spawn(command, args, {
      cwd,
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    // Log agent output for debugging
    this.agentProcess.stdout?.on("data", (data) => {
      if (process.env.DEBUG_AGENT) {
        console.log(`[Agent stdout] ${data.toString().trim()}`);
      }
    });

    this.agentProcess.stderr?.on("data", (data) => {
      if (process.env.DEBUG_AGENT) {
        console.error(`[Agent stderr] ${data.toString().trim()}`);
      }
    });

    this.agentProcess.on("error", (error) => {
      console.error(`[TestProject] Agent process error:`, error);
    });

    this.agentProcess.on("close", (code) => {
      if (!this.cleanedUp) {
        console.log(`[TestProject] Agent exited with code ${code}`);
      }
    });

    // Wait for agent to be ready
    await waitFor(
      async () => {
        try {
          const health = await this.client.ping();
          return health?.agentId === agentId;
        } catch {
          return false;
        }
      },
      {
        timeout,
        interval: 500,
        message: `Agent failed to start on port ${this.port}`,
      },
    );

    console.log(`[TestProject] Agent is ready on port ${this.port}`);
  }

  /**
   * Clean up the test project (stop agent, remove directory)
   */
  async cleanup(): Promise<void> {
    if (this.cleanedUp) return;
    this.cleanedUp = true;

    console.log(`[TestProject] Cleaning up...`);

    // Stop the agent
    if (this.agentProcess) {
      this.agentProcess.kill("SIGTERM");

      // Wait for graceful shutdown
      await new Promise<void>((resolve) => {
        const timeout = setTimeout(() => {
          this.agentProcess?.kill("SIGKILL");
          resolve();
        }, 5000);

        this.agentProcess?.on("close", () => {
          clearTimeout(timeout);
          resolve();
        });
      });

      this.agentProcess = null;
    }

    // Remove project directory
    if (!this.keepOnCleanup) {
      await rm(this.projectDir, { recursive: true, force: true });
      console.log(`[TestProject] Removed ${this.projectDir}`);
    } else {
      console.log(`[TestProject] Keeping ${this.projectDir} for inspection`);
    }
  }

  /**
   * Get a new HTTP client instance for this project
   */
  getClient(): AgentHttpClient {
    return new AgentHttpClient("localhost", this.port, this.token);
  }

  /**
   * Check if the agent is healthy
   */
  async isHealthy(): Promise<boolean> {
    const health = await this.client.ping();
    return health !== null;
  }
}

/**
 * Helper to run a test with a temporary project
 *
 * @example
 * await withTestProject({ template: "minimal" }, async (project) => {
 *   const packages = await project.client.getPackages();
 *   expect(packages.length).toBeGreaterThan(0);
 * });
 */
export async function withTestProject(
  options: TestProjectOptions,
  fn: (project: TestProject) => Promise<void>,
): Promise<void> {
  const project = await TestProject.create(options);
  try {
    await fn(project);
  } finally {
    await project.cleanup();
  }
}

/**
 * Create a shared test project for a test suite
 * Use this with beforeAll/afterAll for better performance
 *
 * @example
 * describe("integration tests", () => {
 *   const projectRef = createSharedTestProject({ template: "minimal" });
 *
 *   it("can query packages", async () => {
 *     const project = await projectRef.get();
 *     const packages = await project.client.getPackages();
 *     expect(packages).toContain("//");
 *   });
 * });
 */
export function createSharedTestProject(options: TestProjectOptions = {}) {
  let project: TestProject | null = null;
  let setupPromise: Promise<TestProject> | null = null;

  return {
    /**
     * Get the project, creating it if necessary
     */
    async get(): Promise<TestProject> {
      if (project) return project;
      if (setupPromise) return setupPromise;

      setupPromise = TestProject.create(options);
      project = await setupPromise;
      return project;
    },

    /**
     * Clean up the project (call in afterAll)
     */
    async cleanup(): Promise<void> {
      if (project) {
        await project.cleanup();
        project = null;
        setupPromise = null;
      }
    },
  };
}
