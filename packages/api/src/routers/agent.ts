import { TRPCError } from "@trpc/server";
import { z } from "zod/v4";

import { createTRPCRouter, publicProcedure } from "../trpc";

/**
 * Schema definitions for agent/project types
 */
const ProjectSchema = z.object({
  path: z.string(),
  name: z.string(),
  last_opened: z.string(),
  active: z.boolean(),
});

const ProjectListResponseSchema = z.object({
  projects: z.array(ProjectSchema),
});

const ProjectCurrentResponseSchema = z.object({
  has_project: z.boolean(),
  project: ProjectSchema.nullable(),
});

const ProjectOpenResponseSchema = z.object({
  success: z.boolean(),
  project: ProjectSchema,
  devshell: z
    .object({
      in_devshell: z.boolean(),
      has_devshell_env: z.boolean(),
      error: z.string().optional(),
    })
    .optional(),
});

const ProjectValidateResponseSchema = z.object({
  valid: z.boolean(),
  error: z.string().optional(),
  message: z.string().optional(),
});

const AgentHealthSchema = z.object({
  status: z.string(),
  has_project: z.boolean(),
  project_root: z.string().optional(),
});

const ConfigResponseSchema = z.object({
  config: z.record(z.string(), z.unknown()),
  last_updated: z.string(),
  cached: z.boolean().optional(),
  refreshed: z.boolean().optional(),
});

/**
 * Helper to build agent base URL from config
 * In a real setup, this would come from environment or context
 */
function getAgentBaseUrl(host = "localhost", port = 9876): string {
  return `http://${host}:${port}`;
}

/**
 * Helper to make authenticated requests to the agent
 */
async function agentFetch<T>(
  path: string,
  options: {
    method?: "GET" | "POST" | "DELETE";
    body?: unknown;
    token?: string;
    host?: string;
    port?: number;
  } = {},
): Promise<T> {
  const { method = "GET", body, token, host, port } = options;
  const baseUrl = getAgentBaseUrl(host, port);

  const headers: Record<string, string> = {};
  if (body) {
    headers["Content-Type"] = "application/json";
  }
  if (token) {
    headers["X-Stackpanel-Token"] = token;
  }

  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    const errorData = (await res.json().catch(() => ({}))) as {
      message?: string;
      error?: string;
    };
    throw new TRPCError({
      code: "BAD_REQUEST",
      message:
        errorData.message ||
        errorData.error ||
        `Agent request failed: ${res.status}`,
    });
  }

  return res.json() as Promise<T>;
}

/**
 * Agent router for project management and agent communication
 */
export const agentRouter = createTRPCRouter({
  /**
   * Check agent health/availability (public, no auth required)
   */
  health: publicProcedure
    .input(
      z
        .object({
          host: z.string().default("localhost"),
          port: z.number().default(9876),
        })
        .optional(),
    )
    .query(async ({ input }) => {
      const host = input?.host ?? "localhost";
      const port = input?.port ?? 9876;

      try {
        const data = await agentFetch<z.infer<typeof AgentHealthSchema>>(
          "/health",
          { host, port },
        );
        return {
          available: true,
          ...data,
        };
      } catch {
        return {
          available: false,
          status: "unavailable",
          has_project: false,
        };
      }
    }),

  /**
   * List all known projects (public endpoint on agent)
   */
  listProjects: publicProcedure
    .input(
      z
        .object({
          host: z.string().default("localhost"),
          port: z.number().default(9876),
        })
        .optional(),
    )
    .query(async ({ input }) => {
      const host = input?.host ?? "localhost";
      const port = input?.port ?? 9876;

      const data = await agentFetch<z.infer<typeof ProjectListResponseSchema>>(
        "/api/project/list",
        { host, port },
      );
      return data.projects;
    }),

  /**
   * Get current active project (public endpoint on agent)
   */
  currentProject: publicProcedure
    .input(
      z
        .object({
          host: z.string().default("localhost"),
          port: z.number().default(9876),
        })
        .optional(),
    )
    .query(async ({ input }) => {
      const host = input?.host ?? "localhost";
      const port = input?.port ?? 9876;

      const data = await agentFetch<
        z.infer<typeof ProjectCurrentResponseSchema>
      >("/api/project/current", { host, port });
      return data;
    }),

  /**
   * Open/switch to a project (requires auth token)
   */
  openProject: publicProcedure
    .input(
      z.object({
        path: z.string().min(1, "Project path is required"),
        token: z.string().min(1, "Agent token is required"),
        host: z.string().default("localhost"),
        port: z.number().default(9876),
      }),
    )
    .mutation(async ({ input }) => {
      const { path, token, host, port } = input;

      const data = await agentFetch<z.infer<typeof ProjectOpenResponseSchema>>(
        "/api/project/open",
        {
          method: "POST",
          body: { path },
          token,
          host,
          port,
        },
      );
      return data;
    }),

  /**
   * Close the current project (requires auth token)
   */
  closeProject: publicProcedure
    .input(
      z.object({
        token: z.string().min(1, "Agent token is required"),
        host: z.string().default("localhost"),
        port: z.number().default(9876),
      }),
    )
    .mutation(async ({ input }) => {
      const { token, host, port } = input;

      await agentFetch<{ success: boolean }>("/api/project/close", {
        method: "POST",
        token,
        host,
        port,
      });
      return { success: true };
    }),

  /**
   * Validate a project path (requires auth token)
   */
  validateProject: publicProcedure
    .input(
      z.object({
        path: z.string().min(1, "Project path is required"),
        token: z.string().min(1, "Agent token is required"),
        host: z.string().default("localhost"),
        port: z.number().default(9876),
      }),
    )
    .mutation(async ({ input }) => {
      const { path, token, host, port } = input;

      const data = await agentFetch<
        z.infer<typeof ProjectValidateResponseSchema>
      >("/api/project/validate", {
        method: "POST",
        body: { path },
        token,
        host,
        port,
      });
      return data;
    }),

  /**
   * Remove a project from the known projects list (requires auth token)
   */
  removeProject: publicProcedure
    .input(
      z.object({
        path: z.string().min(1, "Project path is required"),
        token: z.string().min(1, "Agent token is required"),
        host: z.string().default("localhost"),
        port: z.number().default(9876),
      }),
    )
    .mutation(async ({ input }) => {
      const { path, token, host, port } = input;

      await agentFetch<{ success: boolean }>(
        `/api/project/remove?path=${encodeURIComponent(path)}`,
        {
          method: "DELETE",
          token,
          host,
          port,
        },
      );
      return { success: true };
    }),

  /**
   * Get the current Stackpanel config (may be cached)
   */
  getConfig: publicProcedure
    .input(
      z.object({
        token: z.string().min(1, "Agent token is required"),
        host: z.string().default("localhost"),
        port: z.number().default(9876),
        refresh: z.boolean().default(false),
      }),
    )
    .query(async ({ input }) => {
      const { token, host, port, refresh } = input;
      const url = refresh ? "/api/nix/config?refresh=true" : "/api/nix/config";

      const data = await agentFetch<z.infer<typeof ConfigResponseSchema>>(url, {
        token,
        host,
        port,
      });
      return data;
    }),

  /**
   * Force refresh the Stackpanel config by re-evaluating the flake
   */
  refreshConfig: publicProcedure
    .input(
      z.object({
        token: z.string().min(1, "Agent token is required"),
        host: z.string().default("localhost"),
        port: z.number().default(9876),
      }),
    )
    .mutation(async ({ input }) => {
      const { token, host, port } = input;

      const data = await agentFetch<z.infer<typeof ConfigResponseSchema>>(
        "/api/nix/config",
        {
          method: "POST",
          token,
          host,
          port,
        },
      );
      return data;
    }),
});

export type AgentRouter = typeof agentRouter;
