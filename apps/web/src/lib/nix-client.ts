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

import type {
  App,
  Service,
  StackpanelConfig,
  DataResponse,
  WriteResponse,
  DeleteResponse,
  ListResponse,
} from "./types";
import { kebabToSnake, snakeToKebab } from "./nix-data";

// Re-export types for convenience
export type { App, Service, StackpanelConfig };

// =============================================================================
// Entity Builder - Provides typed CRUD for a specific entity
// =============================================================================

/**
 * EntityClient provides typed CRUD operations for a single entity type.
 * Similar to Drizzle's table interface.
 */
export class EntityClient<T> {
  constructor(
    private readonly client: NixClient,
    private readonly entityName: string,
  ) {}

  /**
   * Get the entity data, or null if it doesn't exist.
   * Transforms kebab-case keys from Nix to snake_case for proto types.
   */
  async get(): Promise<T | null> {
    const res = await this.client.fetch<DataResponse<T>>(
      `/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
    );
    return res.exists && res.data ? kebabToSnake(res.data) : null;
  }

  /**
   * Check if the entity exists.
   */
  async exists(): Promise<boolean> {
    const res = await this.client.fetch<DataResponse<T>>(
      `/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
    );
    return res.exists;
  }

  /**
   * Set the entity data (full replacement).
   * Transforms snake_case keys to kebab-case for Nix.
   */
  async set(data: T): Promise<WriteResponse> {
    return this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      data: snakeToKebab(data),
    });
  }

  /**
   * Delete the entity.
   */
  async delete(): Promise<DeleteResponse> {
    return this.client.delete<DeleteResponse>(
      `/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
    );
  }

  /**
   * Update entity data by merging with existing data.
   * Fetches current data, merges with updates, then writes back.
   */
  async update(updates: Partial<T>): Promise<WriteResponse> {
    const current = await this.get();
    const merged = { ...current, ...updates } as T;
    return this.set(merged);
  }
}

/**
 * MapEntityClient provides typed CRUD for entities that are key-value maps.
 * Useful for apps, services, etc. where each key is an identifier.
 */
export class MapEntityClient<V> {
  constructor(
    private readonly client: NixClient,
    private readonly entityName: string,
  ) {}

  /**
   * Get all entries.
   * Transforms kebab-case keys from Nix to snake_case for proto types.
   */
  async all(): Promise<Record<string, V>> {
    console.log("[NixClient] fetching all", { entity: this.entityName });
    const res = await this.client.fetch<DataResponse<Record<string, V>>>(
      `/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
    );
    console.log("[NixClient] raw response", res);
    const result = res.exists && res.data ? kebabToSnake(res.data) : {};
    console.log("[NixClient] transformed result", result);
    return result;
  }

  /**
   * Get a single entry by key.
   */
  async get(key: string): Promise<V | null> {
    const all = await this.all();
    return all[key] ?? null;
  }

  /**
   * Check if a key exists.
   */
  async has(key: string): Promise<boolean> {
    const all = await this.all();
    return key in all;
  }

  /**
   * Set a single entry (upsert).
   * Transforms snake_case keys to kebab-case for Nix.
   */
  async set(key: string, value: V): Promise<WriteResponse> {
    const all = await this.all();
    all[key] = value;
    return this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      data: snakeToKebab(all),
    });
  }

  /**
   * Update a single entry by merging.
   * Transforms snake_case keys to kebab-case for Nix.
   */
  async update(key: string, updates: Partial<V>): Promise<WriteResponse> {
    console.log("[NixClient] update called", {
      entity: this.entityName,
      key,
      updates,
    });
    const all = await this.all();
    console.log("[NixClient] current data (snake_case)", all);
    const current = all[key] ?? ({} as V);
    all[key] = { ...current, ...updates };
    console.log("[NixClient] merged data (snake_case)", all);
    const kebabData = snakeToKebab(all);
    console.log("[NixClient] data to write (kebab-case)", kebabData);
    const result = await this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      data: kebabData,
    });
    console.log("[NixClient] write result", result);
    return result;
  }

  /**
   * Delete a single entry.
   * Transforms snake_case keys to kebab-case for Nix.
   */
  async remove(key: string): Promise<WriteResponse> {
    const all = await this.all();
    delete all[key];
    return this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      data: snakeToKebab(all),
    });
  }

  /**
   * Set all entries (full replacement).
   * Transforms snake_case keys to kebab-case for Nix.
   */
  async setAll(data: Record<string, V>): Promise<WriteResponse> {
    return this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      data: snakeToKebab(data),
    });
  }

  /**
   * Delete the entire entity file.
   */
  async deleteAll(): Promise<DeleteResponse> {
    return this.client.delete<DeleteResponse>(
      `/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
    );
  }

  /**
   * List all keys.
   */
  async keys(): Promise<string[]> {
    const all = await this.all();
    return Object.keys(all);
  }

  /**
   * List all values.
   */
  async values(): Promise<V[]> {
    const all = await this.all();
    return Object.values(all);
  }

  /**
   * List all entries as [key, value] pairs.
   */
  async entries(): Promise<[string, V][]> {
    const all = await this.all();
    return Object.entries(all);
  }
}

// =============================================================================
// Main Client
// =============================================================================

export interface NixClientConfig {
  baseUrl?: string;
  token?: string;
}

/**
 * NixClient provides a Drizzle-like interface for Nix-as-database.
 *
 * @example
 * ```ts
 * const nix = new NixClient({ token: 'xxx' });
 *
 * // Read config (evaluated from Nix)
 * const config = await nix.config();
 *
 * // Work with data entities (stored in .stackpanel/data/)
 * const apps = await nix.data.apps.all();
 * await nix.data.apps.set('web', { port: 3000, tls: true });
 *
 * // Custom entities
 * const settings = nix.entity<MySettings>('settings');
 * await settings.set({ theme: 'dark' });
 * ```
 */
export class NixClient {
  private readonly baseUrl: string;
  private token?: string;

  // Pre-configured data entity clients
  readonly data = {
    /** App configurations (map of name -> App) */
    apps: new MapEntityClient<App>(this, "apps"),

    /** Service configurations (map of key -> Service) */
    services: new MapEntityClient<Service>(this, "services"),
  };

  constructor(config: NixClientConfig = {}) {
    this.baseUrl = config.baseUrl ?? "http://localhost:9876";
    this.token = config.token;
  }

  /**
   * Set the auth token.
   */
  setToken(token?: string): void {
    this.token = token;
  }

  /**
   * Get the full stackpanel config by evaluating the Nix expression.
   * This reads the computed config, not raw data files.
   *
   * STACKPANEL_NIX_CONFIG points to the source .nix file (.stackpanel/config.nix)
   * STACKPANEL_CONFIG_JSON points to the pre-computed JSON in the Nix store
   *
   * We use the JSON version here since it's already evaluated and faster.
   */
  async config(): Promise<StackpanelConfig> {
    return this.eval<StackpanelConfig>(
      'builtins.fromJSON (builtins.readFile (builtins.getEnv "STACKPANEL_CONFIG_JSON"))',
    );
  }

  /**
   * Evaluate an arbitrary Nix expression.
   */
  async eval<T = unknown>(expression: string): Promise<T> {
    return this.post<T>("/api/nix/eval", { expression });
  }

  /**
   * List all data entities (files in .stackpanel/data/).
   */
  async listEntities(): Promise<string[]> {
    const res = await this.fetch<ListResponse>("/api/nix/data/list");
    return res.entities;
  }

  /**
   * Create a typed entity client for custom data.
   */
  entity<T>(name: string): EntityClient<T> {
    return new EntityClient<T>(this, name);
  }

  /**
   * Create a typed map entity client for custom key-value data.
   */
  mapEntity<V>(name: string): MapEntityClient<V> {
    return new MapEntityClient<V>(this, name);
  }

  // =========================================================================
  // Internal HTTP helpers
  // =========================================================================

  /** @internal */
  async fetch<T>(path: string): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      headers: this.headers(),
    });
    return this.handleResponse<T>(res);
  }

  /** @internal */
  async post<T>(path: string, body: unknown): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "POST",
      headers: this.headers(true),
      body: JSON.stringify(body),
    });
    return this.handleResponse<T>(res);
  }

  /** @internal */
  async delete<T>(path: string): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "DELETE",
      headers: this.headers(),
    });
    return this.handleResponse<T>(res);
  }

  private headers(json = false): Record<string, string> {
    const h: Record<string, string> = {};
    if (json) h["Content-Type"] = "application/json";
    if (this.token) h["X-Stackpanel-Token"] = this.token;
    return h;
  }

  private async handleResponse<T>(res: Response): Promise<T> {
    const data = await res.json();
    if (!data.success) {
      throw new Error(data.error ?? "Unknown error");
    }
    return data.data as T;
  }
}

// =============================================================================
// Default Export
// =============================================================================

/** Default NixClient instance */
export const nixClient = new NixClient();
