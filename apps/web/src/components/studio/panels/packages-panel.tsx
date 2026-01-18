"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Database, Loader2, Package, Search, X } from "lucide-react";
import {
	DataSourceIndicator,
	PackageCard,
	SearchErrorMessage,
	usePackages,
} from "./packages";
import { PanelHeader } from "./shared/panel-header";

export function PackagesPanel() {
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
		installedCount,
		userInstalledPackages,
		devshellPackages,
		processingPackages,
		handleAddPackage,
		handleRemovePackage,
		isPackageInstalled,
		isUserInstalledPackage,
		showInstalled,
		setShowInstalled,
	} = usePackages();

	return (
		<div className="space-y-6">
			<PanelHeader
				title="Packages"
				description="Search and add packages from nixpkgs to your development environment"
				guideKey="packages"
				actions={
					<div className="flex items-center gap-4 text-xs text-muted-foreground">
						{!query && installedCount > 0 && (
							<span className="text-green-600 dark:text-green-400">
								{installedCount} installed
							</span>
						)}
						{cacheStats && cacheStats.packageCount > 0 && (
							<span>{cacheStats.packageCount.toLocaleString()} cached</span>
						)}
						{!query && (
							<div className="flex items-center gap-2">
								<Label
									htmlFor="show-installed-packages"
									className="text-xs text-muted-foreground"
								>
									Show installed
								</Label>
								<Switch
									id="show-installed-packages"
									checked={showInstalled}
									onCheckedChange={setShowInstalled}
								/>
							</div>
						)}
					</div>
				}
			/>

			{/* Search Controls */}
			<div className="relative">
				{isLoading || isRefreshing ? (
					<Loader2 className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-accent animate-spin" />
				) : (
					<Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
				)}
				<Input
					value={query}
					onChange={(e) => setQuery(e.target.value)}
					placeholder="Search nixpkgs packages..."
					className="pl-9 pr-9"
				/>
				{query && (
					<button
						onClick={clear}
						className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
					>
						<X className="h-4 w-4" />
					</button>
				)}
			</div>

			{/* Results Info with Data Source */}
			{query && !isLoading && !error && (
				<div className="flex items-center justify-between">
					<div className="text-sm text-muted-foreground">
						{total > 0 ? (
							<>
								Found <strong>{total.toLocaleString()}</strong> packages
								matching "{query}"
							</>
						) : (
							<>No packages found matching "{query}"</>
						)}
					</div>
					{dataSource && (
						<DataSourceIndicator
							source={dataSource}
							isRefreshing={isRefreshing}
							cacheStats={cacheStats}
						/>
					)}
				</div>
			)}

			{/* Error State */}
			{error && <SearchErrorMessage error={error} />}

			{/* Loading State (initial, no cached results) */}
			{isLoading && packages.length === 0 && (
				<div className="flex flex-col items-center justify-center py-12 gap-3">
					<Loader2 className="h-8 w-8 animate-spin text-accent" />
					<p className="text-sm text-muted-foreground">Searching nixpkgs...</p>
				</div>
			)}

			{/* Empty State */}
			{!query &&
				!isLoading &&
				!error &&
				(!showInstalled || installedCount === 0) && (
					<div className="flex flex-col items-center justify-center py-12 text-center">
						<div className="flex h-16 w-16 items-center justify-center rounded-full bg-accent/10">
							<Package className="h-8 w-8 text-accent" />
						</div>
						<h3 className="mt-4 font-medium text-foreground">Search Nixpkgs</h3>
						<p className="mt-2 max-w-sm text-muted-foreground text-sm">
							Search over 100,000 packages in the Nix package collection. Find
							tools, libraries, and applications for your development
							environment.
						</p>
						{installedCount > 0 && !showInstalled && (
							<p className="mt-3 text-xs text-muted-foreground">
								Toggle "Show installed" to view your current packages.
							</p>
						)}
						{cacheStats && cacheStats.packageCount > 0 && (
							<p className="mt-3 text-xs text-muted-foreground">
								<Database className="inline h-3 w-3 mr-1" />
								{cacheStats.packageCount.toLocaleString()} packages cached for
								instant results
							</p>
						)}
					</div>
				)}

			{/* User-installed packages section */}
			{showInstalled && userInstalledPackages.length > 0 && !query && (
				<div className="space-y-3">
					<div className="flex items-center justify-between">
						<h3 className="text-sm font-medium text-muted-foreground">
							User-installed packages
						</h3>
						<Badge variant="secondary" className="text-xs">
							{userInstalledPackages.length}
						</Badge>
					</div>
					<div className="grid gap-4 sm:grid-cols-2">
						{userInstalledPackages.map((pkg) => {
							const attrPath = pkg.attrPath || pkg.name;
							const processing = processingPackages.get(attrPath);
							return (
								<PackageCard
									key={attrPath}
									pkg={{
										name: pkg.name,
										attr_path: attrPath,
										version: pkg.version || "",
										description: "",
									}}
									isInstalled={true}
									isUserInstalled={true}
									isCompact={true}
									isRemoving={processing === "removing"}
									onRemove={(p) => handleRemovePackage(p)}
								/>
							);
						})}
					</div>
				</div>
			)}

			{/* Devshell packages section */}
			{showInstalled && devshellPackages.length > 0 && !query && (
				<div className="space-y-3">
					<div className="flex items-center justify-between">
						<h3 className="text-sm font-medium text-muted-foreground">
							From devshell config
						</h3>
						<Badge variant="secondary" className="text-xs">
							{devshellPackages.length}
						</Badge>
					</div>
					<div className="text-xs text-muted-foreground">
						These packages are defined in your Nix configuration and cannot be
						removed from the UI.
					</div>
					<div className="grid gap-4 sm:grid-cols-2">
						{devshellPackages.map((pkg) => {
							const attrPath = pkg.attrPath || pkg.name;
							return (
								<PackageCard
									key={attrPath}
									pkg={{
										name: pkg.name,
										attr_path: attrPath,
										version: pkg.version || "",
										description: "",
									}}
									isInstalled={true}
									isUserInstalled={false}
									isCompact={true}
								/>
							);
						})}
					</div>
				</div>
			)}

			{/* Search Results */}
			{packages.length > 0 && query && (
				<div className="space-y-3">
					{packages.map((pkg) => {
						const installed = isPackageInstalled(pkg);
						const userInstalled = isUserInstalledPackage(pkg);
						const processing = processingPackages.get(pkg.attr_path);
						return (
							<PackageCard
								key={pkg.attr_path}
								pkg={pkg}
								isInstalled={installed}
								isUserInstalled={userInstalled}
								isAdding={processing === "adding"}
								isRemoving={processing === "removing"}
								onAdd={installed ? undefined : handleAddPackage}
								onRemove={userInstalled ? handleRemovePackage : undefined}
							/>
						);
					})}
				</div>
			)}

			{/* Load More */}
			{hasMore && (
				<div className="flex justify-center pt-4">
					<Button
						variant="outline"
						onClick={loadMore}
						disabled={isLoading || isRefreshing}
						className="gap-2"
					>
						{isLoading || isRefreshing ? (
							<>
								<Loader2 className="h-4 w-4 animate-spin" />
								Loading...
							</>
						) : (
							<>
								Load More
								<Badge variant="secondary" className="ml-1">
									{packages.length} / {total}
								</Badge>
							</>
						)}
					</Button>
				</div>
			)}
		</div>
	);
}
