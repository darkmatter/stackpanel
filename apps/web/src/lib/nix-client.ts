/**
 * NixClient - A Drizzle-like typed client for Nix-as-database
 *
 * Provides typed CRUD operations on Nix data files stored in .stackpanel/data/
 * Each "entity" maps to a .nix file that can be read, written, and deleted.
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
	 */
	async get(): Promise<T | null> {
		const res = await this.client.fetch<DataResponse<T>>(
			`/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
		);
		return res.exists ? res.data : null;
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
	 */
	async set(data: T): Promise<WriteResponse> {
		return this.client.post<WriteResponse>("/api/nix/data", {
			entity: this.entityName,
			data,
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
	 */
	async all(): Promise<Record<string, V>> {
		const res = await this.client.fetch<DataResponse<Record<string, V>>>(
			`/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
		);
		return res.exists && res.data ? res.data : {};
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
	 */
	async set(key: string, value: V): Promise<WriteResponse> {
		const all = await this.all();
		all[key] = value;
		return this.client.post<WriteResponse>("/api/nix/data", {
			entity: this.entityName,
			data: all,
		});
	}

	/**
	 * Update a single entry by merging.
	 */
	async update(key: string, updates: Partial<V>): Promise<WriteResponse> {
		const all = await this.all();
		const current = all[key] ?? ({} as V);
		all[key] = { ...current, ...updates };
		return this.client.post<WriteResponse>("/api/nix/data", {
			entity: this.entityName,
			data: all,
		});
	}

	/**
	 * Delete a single entry.
	 */
	async remove(key: string): Promise<WriteResponse> {
		const all = await this.all();
		delete all[key];
		return this.client.post<WriteResponse>("/api/nix/data", {
			entity: this.entityName,
			data: all,
		});
	}

	/**
	 * Set all entries (full replacement).
	 */
	async setAll(data: Record<string, V>): Promise<WriteResponse> {
		return this.client.post<WriteResponse>("/api/nix/data", {
			entity: this.entityName,
			data,
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
	 */
	async config(): Promise<StackpanelConfig> {
		return this.eval<StackpanelConfig>(
			'import (builtins.getEnv "STACKPANEL_NIX_CONFIG")',
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
