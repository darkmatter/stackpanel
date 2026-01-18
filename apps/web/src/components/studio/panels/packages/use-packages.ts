/**
 * Hook for managing packages panel state.
 */
import { useCallback, useState } from "react";
import type { NixpkgsPackage } from "@/lib/types";
import { useInstalledPackages } from "@/lib/use-installed-packages";
import { useNixData } from "@/lib/use-nix-config";
import { useNixpkgsSearch } from "@/lib/use-nixpkgs-search";
import type { ProcessingStatus } from "./types";

export function usePackages() {
	const {
		query,
		setQuery,
		packages,
		total,
		isLoading,
		isRefreshing,
		error,
		hasMore,
		loadMore,
		clear,
		dataSource,
		cacheStats,
	} = useNixpkgsSearch();

	// Fetch installed packages separately for accurate status across the UI
	const {
		packages: installedPackages,
		isInstalled: checkInstalled,
		count: installedCount,
		refresh: refreshInstalled,
	} = useInstalledPackages();

	// User packages from .stackpanel/data/packages.nix
	const { data: userPackages, mutate: setUserPackages } = useNixData<string[]>(
		"packages",
		{ initialData: [] },
	);

	// Track packages currently being added/removed
	const [processingPackages, setProcessingPackages] = useState<
		Map<string, ProcessingStatus>
	>(new Map());
	const [showInstalled, setShowInstalled] = useState(true);

	// Add a package to user packages
	const handleAddPackage = useCallback(
		async (pkg: NixpkgsPackage) => {
			const attrPath = pkg.attr_path;
			const currentPackages = userPackages ?? [];

			// Don't add if already in list
			if (currentPackages.includes(attrPath)) {
				return;
			}

			setProcessingPackages((prev) => new Map(prev).set(attrPath, "adding"));

			try {
				const newPackages = [...currentPackages, attrPath];
				await setUserPackages(newPackages);
				// Refresh installed packages to reflect the change
				await refreshInstalled();
			} catch (err) {
				console.error("Failed to add package:", err);
			} finally {
				setProcessingPackages((prev) => {
					const next = new Map(prev);
					next.delete(attrPath);
					return next;
				});
			}
		},
		[userPackages, setUserPackages, refreshInstalled],
	);

	// Remove a package from user packages
	const handleRemovePackage = useCallback(
		async (pkg: NixpkgsPackage) => {
			const attrPath = pkg.attr_path;
			const currentPackages = userPackages ?? [];

			setProcessingPackages((prev) => new Map(prev).set(attrPath, "removing"));

			try {
				const newPackages = currentPackages.filter((p) => p !== attrPath);
				await setUserPackages(newPackages);
				// Refresh installed packages to reflect the change
				await refreshInstalled();
			} catch (err) {
				console.error("Failed to remove package:", err);
			} finally {
				setProcessingPackages((prev) => {
					const next = new Map(prev);
					next.delete(attrPath);
					return next;
				});
			}
		},
		[userPackages, setUserPackages, refreshInstalled],
	);

	// Check if a package is installed (from any source)
	const isPackageInstalled = useCallback(
		(pkg: NixpkgsPackage): boolean => {
			return checkInstalled(pkg.name) || checkInstalled(pkg.attr_path);
		},
		[checkInstalled],
	);

	// Check if a package is user-installed (from .stackpanel/data/packages.nix)
	const isUserInstalledPackage = useCallback(
		(pkg: NixpkgsPackage): boolean => {
			const currentPackages = userPackages ?? [];
			return currentPackages.includes(pkg.attr_path);
		},
		[userPackages],
	);

	// Get user-installed packages for display
	const userInstalledPackages = installedPackages.filter(
		(pkg) => pkg.source === "user",
	);

	// Get devshell packages (from Nix config)
	const devshellPackages = installedPackages.filter(
		(pkg) => pkg.source !== "user",
	);

	return {
		// Search state
		query,
		setQuery,
		packages,
		total,
		isLoading,
		isRefreshing,
		error,
		hasMore,
		loadMore,
		clear,
		dataSource,
		cacheStats,

		// Installed packages
		installedCount,
		userInstalledPackages,
		devshellPackages,

		// Package actions
		processingPackages,
		handleAddPackage,
		handleRemovePackage,
		isPackageInstalled,
		isUserInstalledPackage,

		// UI state
		showInstalled,
		setShowInstalled,
	};
}
