/**
 * Type definitions for the packages panel.
 */
import type { NixpkgsPackage } from "@/lib/types";

export type { NixpkgsPackage };

export interface PackageCardProps {
	pkg: NixpkgsPackage;
	isInstalled?: boolean;
	isUserInstalled?: boolean;
	isAdding?: boolean;
	isRemoving?: boolean;
	isCompact?: boolean;
	onAdd?: (pkg: NixpkgsPackage) => void;
	onRemove?: (pkg: NixpkgsPackage) => void;
}

export interface SearchErrorMessageProps {
	error: Error;
}

export interface DataSourceIndicatorProps {
	source: "fresh" | "cache" | "local" | "nixhub" | null;
	isRefreshing: boolean;
	cacheStats: { packageCount: number; searchCount: number } | null;
}

export type ProcessingStatus = "adding" | "removing";
