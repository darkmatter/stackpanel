/**
 * Type definitions for Databases Panel
 */

export interface DatabaseStorage {
	used: number;
	total: number;
}

export interface Database {
	name: string;
	type: string;
	version: string;
	status: "online" | "offline";
	connections: string;
	storage: DatabaseStorage;
	host: string;
	lastBackup: string;
	ssl: boolean;
}

export interface CreateDatabaseDialogProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	dbName: string;
	onDbNameChange: (name: string) => void;
	seedSnapshot: string;
	onSeedSnapshotChange: (snapshot: string) => void;
	runMigrations: boolean;
	onRunMigrationsChange: (run: boolean) => void;
	onProvision: () => void;
	onClose: () => void;
	isProvisioning: boolean;
	provisioningComplete: boolean;
	provisioningSuccess: boolean;
	provisioningError: string | null;
	workflowRunUrl: string | null;
	workflowStatus: string | null;
	isPaired: boolean;
	snapshots: Array<{ key: string; description?: string; isDefault?: boolean }>;
	snapshotsLoading: boolean;
}

export interface DatabaseCardProps {
	database: Database;
}

export interface ProvisioningStatusProps {
	isProvisioning: boolean;
	provisioningComplete: boolean;
	provisioningSuccess: boolean;
	dbName: string;
	workflowRunUrl: string | null;
	onClose: () => void;
	onRetry: () => void;
	workflowStatus: string | null;
}
