/**
 * IndexedDB cache for nixpkgs packages
 *
 * Provides fast local search results while fresh data is being fetched.
 * Packages are stored with their search terms for quick lookup.
 */

import { type DBSchema, type IDBPDatabase, openDB } from "idb";
import type { NixpkgsPackage } from "./types";

// =============================================================================
// Schema
// =============================================================================

interface NixpkgsCacheSchema extends DBSchema {
	packages: {
		key: string; // attr_path
		value: CachedPackage;
		indexes: {
			"by-name": string;
			"by-updated": number;
		};
	};
	searchResults: {
		key: string; // query string
		value: CachedSearchResult;
		indexes: {
			"by-updated": number;
		};
	};
	metadata: {
		key: string;
		value: CacheMetadata;
	};
}

interface CachedPackage extends Omit<NixpkgsPackage, "installed"> {
	/** When this package was last updated */
	updated_at: number;
	/** Search terms this package matches (for local search) */
	search_terms: string;
	/** Whether this package was marked as installed at cache time */
	installed?: boolean;
}

interface CachedSearchResult {
	/** The search query */
	query: string;
	/** Attribute paths of matching packages (in order) */
	package_attrs: string[];
	/** Total count from server */
	total: number;
	/** When this result was cached */
	cached_at: number;
}

interface CacheMetadata {
	key: string;
	value: string | number;
}

// =============================================================================
// Cache Constants
// =============================================================================

const DB_NAME = "stackpanel-nixpkgs-cache";
const DB_VERSION = 1;

/** How long search results are considered fresh (5 minutes) */
const SEARCH_RESULT_TTL = 5 * 60 * 1000;

/** Maximum number of cached search queries */
const MAX_CACHED_SEARCHES = 100;

// =============================================================================
// Cache Class
// =============================================================================

export class NixpkgsCache {
	private db: IDBPDatabase<NixpkgsCacheSchema> | null = null;
	private initPromise: Promise<void> | null = null;

	/**
	 * Initialize the database connection
	 */
	private async init(): Promise<void> {
		if (this.db) return;
		if (this.initPromise) return this.initPromise;

		this.initPromise = (async () => {
			this.db = await openDB<NixpkgsCacheSchema>(DB_NAME, DB_VERSION, {
				upgrade(db) {
					// Packages store
					if (!db.objectStoreNames.contains("packages")) {
						const packagesStore = db.createObjectStore("packages", {
							keyPath: "attr_path",
						});
						packagesStore.createIndex("by-name", "name");
						packagesStore.createIndex("by-updated", "updated_at");
					}

					// Search results store
					if (!db.objectStoreNames.contains("searchResults")) {
						const searchStore = db.createObjectStore("searchResults", {
							keyPath: "query",
						});
						searchStore.createIndex("by-updated", "cached_at");
					}

					// Metadata store
					if (!db.objectStoreNames.contains("metadata")) {
						db.createObjectStore("metadata", { keyPath: "key" });
					}
				},
			});
		})();

		return this.initPromise;
	}

	/**
	 * Get cached search results for a query
	 */
	async getCachedSearch(query: string): Promise<{
		packages: NixpkgsPackage[];
		total: number;
		isFresh: boolean;
	} | null> {
		await this.init();
		if (!this.db) return null;

		const normalizedQuery = query.toLowerCase().trim();
		const cached = await this.db.get("searchResults", normalizedQuery);

		if (!cached) return null;

		const isFresh = Date.now() - cached.cached_at < SEARCH_RESULT_TTL;

		// Fetch the actual package data
		const packages: NixpkgsPackage[] = [];
		for (const attrPath of cached.package_attrs) {
			const pkg = await this.db.get("packages", attrPath);
			if (pkg) {
				packages.push({
					name: pkg.name,
					attr_path: pkg.attr_path,
					version: pkg.version,
					description: pkg.description,
					installed: pkg.installed,
					license: pkg.license,
					homepage: pkg.homepage,
				});
			}
		}

		return {
			packages,
			total: cached.total,
			isFresh,
		};
	}

	/**
	 * Cache search results
	 */
	async cacheSearchResults(
		query: string,
		packages: NixpkgsPackage[],
		total: number,
	): Promise<void> {
		await this.init();
		if (!this.db) return;

		const normalizedQuery = query.toLowerCase().trim();
		const now = Date.now();

		// Store individual packages
		const tx = this.db.transaction(["packages", "searchResults"], "readwrite");

		for (const pkg of packages) {
			const cachedPkg: CachedPackage = {
				name: pkg.name,
				attr_path: pkg.attr_path,
				version: pkg.version,
				description: pkg.description,
				installed: pkg.installed,
				license: pkg.license,
				homepage: pkg.homepage,
				updated_at: now,
				search_terms:
					`${pkg.name} ${pkg.attr_path} ${pkg.description ?? ""}`.toLowerCase(),
			};
			await tx.objectStore("packages").put(cachedPkg);
		}

		// Store search result
		const searchResult: CachedSearchResult = {
			query: normalizedQuery,
			package_attrs: packages.map((p) => p.attr_path),
			total,
			cached_at: now,
		};
		await tx.objectStore("searchResults").put(searchResult);

		await tx.done;

		// Cleanup old search results
		await this.cleanupOldSearches();
	}

	/**
	 * Search packages locally in the cache
	 * This provides instant results while the API fetch is in progress
	 */
	async searchLocal(query: string, limit = 20): Promise<NixpkgsPackage[]> {
		await this.init();
		if (!this.db) return [];

		const normalizedQuery = query.toLowerCase().trim();
		if (!normalizedQuery) return [];

		// Get all packages and filter/sort locally
		const allPackages = await this.db.getAll("packages");

		const matches = allPackages
			.filter((pkg) => pkg.search_terms.includes(normalizedQuery))
			.sort((a, b) => {
				// Exact name match first
				const aExact = a.name.toLowerCase() === normalizedQuery;
				const bExact = b.name.toLowerCase() === normalizedQuery;
				if (aExact !== bExact) return aExact ? -1 : 1;

				// Name starts with query
				const aPrefix = a.name.toLowerCase().startsWith(normalizedQuery);
				const bPrefix = b.name.toLowerCase().startsWith(normalizedQuery);
				if (aPrefix !== bPrefix) return aPrefix ? -1 : 1;

				// Alphabetical
				return a.name.localeCompare(b.name);
			})
			.slice(0, limit);

		return matches.map((pkg) => ({
			name: pkg.name,
			attr_path: pkg.attr_path,
			version: pkg.version,
			description: pkg.description,
			installed: pkg.installed,
			license: pkg.license,
			homepage: pkg.homepage,
		}));
	}

	/**
	 * Get cache statistics
	 */
	async getStats(): Promise<{
		packageCount: number;
		searchCount: number;
		lastUpdated: number | null;
	}> {
		await this.init();
		if (!this.db) {
			return { packageCount: 0, searchCount: 0, lastUpdated: null };
		}

		const packageCount = await this.db.count("packages");
		const searchCount = await this.db.count("searchResults");

		const metadata = await this.db.get("metadata", "lastUpdated");
		const lastUpdated = metadata ? Number(metadata.value) : null;

		return { packageCount, searchCount, lastUpdated };
	}

	/**
	 * Clear all cached data
	 */
	async clear(): Promise<void> {
		await this.init();
		if (!this.db) return;

		await this.db.clear("packages");
		await this.db.clear("searchResults");
	}

	/**
	 * Cleanup old search results to prevent unbounded growth
	 */
	private async cleanupOldSearches(): Promise<void> {
		if (!this.db) return;

		const count = await this.db.count("searchResults");
		if (count <= MAX_CACHED_SEARCHES) return;

		// Get oldest searches
		const oldSearches = await this.db.getAllFromIndex(
			"searchResults",
			"by-updated",
		);

		const toDelete = oldSearches.slice(0, count - MAX_CACHED_SEARCHES);

		const tx = this.db.transaction("searchResults", "readwrite");
		for (const search of toDelete) {
			await tx.store.delete(search.query);
		}
		await tx.done;
	}
}

// =============================================================================
// Singleton Export
// =============================================================================

let cacheInstance: NixpkgsCache | null = null;

export function getNixpkgsCache(): NixpkgsCache {
	if (!cacheInstance) {
		cacheInstance = new NixpkgsCache();
	}
	return cacheInstance;
}
