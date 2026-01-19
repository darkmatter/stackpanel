/**
 * Constants and mock data for Databases Panel
 */

import type { Database } from "./types";

export const MOCK_DATABASES: Database[] = [
	{
		name: "main-postgres",
		type: "PostgreSQL",
		version: "15.2",
		status: "online",
		connections: "23/100",
		storage: { used: 12.4, total: 50 },
		host: "main-postgres.internal.acme.com",
		lastBackup: "2 hours ago",
		ssl: true,
	},
	{
		name: "auth-postgres",
		type: "PostgreSQL",
		version: "15.2",
		status: "online",
		connections: "8/50",
		storage: { used: 2.1, total: 20 },
		host: "auth-postgres.internal.acme.com",
		lastBackup: "1 hour ago",
		ssl: true,
	},
	{
		name: "cache-redis",
		type: "Redis",
		version: "7.0",
		status: "online",
		connections: "156/1000",
		storage: { used: 0.8, total: 4 },
		host: "cache-redis.internal.acme.com",
		lastBackup: "N/A",
		ssl: true,
	},
	{
		name: "analytics-clickhouse",
		type: "ClickHouse",
		version: "23.3",
		status: "online",
		connections: "12/50",
		storage: { used: 45.2, total: 200 },
		host: "analytics-clickhouse.internal.acme.com",
		lastBackup: "6 hours ago",
		ssl: true,
	},
];

/**
 * Normalize database name to valid format
 */
export function normalizeDatabaseName(name: string): string {
	return name.toLowerCase().replace(/[^a-z0-9_]/g, "_");
}
