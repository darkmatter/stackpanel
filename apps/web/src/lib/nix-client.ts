/**
 * NixClient - A Drizzle-like typed client for Nix-as-database
 *
 * Provides typed CRUD operations on Nix data files stored in .stackpanel/data/
 * Each "entity" maps to a .nix file that can be read, written, and deleted.
 *
 * Key transformation:
 * - Proto types use snake_case (e.g., install_command)
 * - Nix data files use kebab-case (e.g., install-command)
 * - This client handles the transformation at the boundary
 */

import { agent } from "./agent";
export type {
  App,
  Service,
  StackpanelConfig,
  GeneratedFileWithStatus,
  GeneratedFilesResponse,
} from "./types";

/**
 * Compatibility wrapper: lightweight `NixClient` that delegates to `agent`.
 *
 * This preserves the old `NixClient` API while centralizing implementation
 * on the `AgentHttpClient` singleton exported from `agent.ts`.
 */

export class NixClient {
  constructor(config?: { baseUrl?: string; token?: string }) {
    if (config?.token) agent.setToken(config.token);
    // baseUrl is ignored in favor of the global agent singleton
  }

  setToken(token?: string) {
    agent.setToken(token);
  }

  config(options: { refresh?: boolean } = {}) {
    return agent.nix.config(options as any);
  }

  refreshConfig() {
    return agent.nix.refreshConfig();
  }

  async getGeneratedFiles() {
    const res = await agent.get<any>("/api/nix/files");
    if (!res.success)
      throw new Error(res.error ?? "Failed to get generated files");
    return res.data as GeneratedFilesResponse;
  }

  async eval<T = unknown>(expression: string): Promise<T> {
    return agent.nixEval<T>(expression);
  }

  async listEntities(): Promise<string[]> {
    const res = await agent.get<any>("/api/nix/data/list");
    if (!res.success) throw new Error(res.error ?? "Failed to list entities");
    return res.entities ?? [];
  }

  entity<T>(name: string) {
    return agent.nix.entity<T>(name) as any;
  }

  mapEntity<V>(name: string) {
    return agent.nix.mapEntity<V>(name) as any;
  }
}

export const nixClient = new NixClient();

if (typeof window !== "undefined") {
  (window as any)._nixClient = nixClient;
}
