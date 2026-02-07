/**
 * Shared components for the packages panel.
 */
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import {
	Tooltip,
	TooltipContent,
	TooltipProvider,
	TooltipTrigger,
} from "@ui/tooltip";
import {
	AlertTriangle,
	Check,
	Database,
	ExternalLink,
	Loader2,
	Package,
	Plus,
	RefreshCw,
	Trash2,
	Zap,
} from "lucide-react";
import type {
	DataSourceIndicatorProps,
	PackageCardProps,
	SearchErrorMessageProps,
} from "./types";

export function SearchErrorMessage({ error }: SearchErrorMessageProps) {
	const isNoProject = error.message.includes("no project");

	if (isNoProject) {
		return (
			<div className="rounded-lg border border-amber-500/50 bg-amber-500/10 p-4">
				<div className="flex items-start gap-3">
					<AlertTriangle className="h-5 w-5 text-amber-500 shrink-0 mt-0.5" />
					<div>
						<p className="font-medium text-amber-600 dark:text-amber-400">
							No project connected
						</p>
						<p className="mt-1 text-sm text-muted-foreground">
							Package search requires a connected project with a devshell
							environment. Make sure you have a project open and the agent is
							running.
						</p>
					</div>
				</div>
			</div>
		);
	}

	return (
		<div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4 text-destructive text-sm">
			<p className="font-medium">Failed to search packages</p>
			<p className="mt-1 text-destructive/80">{error.message}</p>
		</div>
	);
}

export function DataSourceIndicator({
	source,
	isRefreshing,
	cacheStats,
}: DataSourceIndicatorProps) {
	if (isRefreshing) {
		return (
			<TooltipProvider>
				<Tooltip>
					<TooltipTrigger asChild>
						<div className="inline-flex items-center gap-1.5 text-xs text-muted-foreground">
							<RefreshCw className="h-3 w-3 animate-spin" />
							<span>Fetching latest...</span>
						</div>
					</TooltipTrigger>
					<TooltipContent>
						Showing cached results while fetching fresh data
					</TooltipContent>
				</Tooltip>
			</TooltipProvider>
		);
	}

	if (source === "fresh") {
		return (
			<TooltipProvider>
				<Tooltip>
					<TooltipTrigger asChild>
						<div className="inline-flex items-center gap-1.5 text-xs text-green-600 dark:text-green-400">
							<Zap className="h-3 w-3" />
							<span>Fresh</span>
						</div>
					</TooltipTrigger>
					<TooltipContent>
						Results fetched from nixpkgs
						{cacheStats && cacheStats.packageCount > 0 && (
							<div className="text-muted-foreground mt-1">
								{cacheStats.packageCount.toLocaleString()} packages cached
							</div>
						)}
					</TooltipContent>
				</Tooltip>
			</TooltipProvider>
		);
	}

	if (source === "cache") {
		return (
			<TooltipProvider>
				<Tooltip>
					<TooltipTrigger asChild>
						<div className="inline-flex items-center gap-1.5 text-xs text-blue-600 dark:text-blue-400">
							<Database className="h-3 w-3" />
							<span>Cached</span>
						</div>
					</TooltipTrigger>
					<TooltipContent>Showing cached results (still fresh)</TooltipContent>
				</Tooltip>
			</TooltipProvider>
		);
	}

	if (source === "local") {
		return (
			<TooltipProvider>
				<Tooltip>
					<TooltipTrigger asChild>
						<div className="inline-flex items-center gap-1.5 text-xs text-amber-600 dark:text-amber-400">
							<Database className="h-3 w-3" />
							<span>Local</span>
						</div>
					</TooltipTrigger>
					<TooltipContent>Searching locally cached packages</TooltipContent>
				</Tooltip>
			</TooltipProvider>
		);
	}

	if (source === "nixhub") {
		return (
			<TooltipProvider>
				<Tooltip>
					<TooltipTrigger asChild>
						<div className="inline-flex items-center gap-1.5 text-xs text-green-600 dark:text-green-400">
							<Zap className="h-3 w-3" />
							<span>Nixhub</span>
						</div>
					</TooltipTrigger>
					<TooltipContent>Results from nixhub.io (fast search)</TooltipContent>
				</Tooltip>
			</TooltipProvider>
		);
	}

	return null;
}

export function PackageCard({
	pkg,
	isInstalled = false,
	isUserInstalled = false,
	isAdding = false,
	isRemoving = false,
	isCompact = false,
	onAdd,
	onRemove,
}: PackageCardProps) {
	const isProcessing = isAdding || isRemoving;

	return (
		<Card
			className={`transition-colors ${isInstalled ? "border-green-500/30 bg-green-600/2" : "hover:border-accent/50"}`}
		>
			<CardContent className={isCompact ? "p-2.5" : "p-4"}>
				<div
					className={`flex items-start justify-between ${isCompact ? "gap-3" : "gap-4"}`}
				>
					<div
						className={`flex items-start min-w-0 flex-1 ${isCompact ? "gap-2.5" : "gap-3"}`}
					>
						<div
							className={`flex shrink-0 items-center justify-center rounded-lg ${isCompact ? "h-8 w-8" : "h-10 w-10"} ${isInstalled ? "bg-green-500/10" : "bg-accent/10"}`}
						>
							{isInstalled ? (
								<Check
									className={
										isCompact
											? "h-4 w-4 text-green-500"
											: "h-5 w-5 text-green-500"
									}
								/>
							) : (
								<Package
									className={
										isCompact ? "h-4 w-4 text-accent" : "h-5 w-5 text-accent"
									}
								/>
							)}
						</div>
						<div className="min-w-0 flex-1">
							<div className="flex items-center gap-2 flex-wrap">
								<h3
									className={`font-medium text-foreground truncate ${isCompact ? "text-sm" : ""}`}
								>
									{pkg.name}
								</h3>
								<Badge variant="secondary" className="text-xs shrink-0">
									{pkg.version}
								</Badge>
								{isInstalled && (
									<Badge
										variant="outline"
										className="text-xs shrink-0 border-green-500/50 text-green-600 dark:text-green-600"
									>
										{isUserInstalled ? "User Installed" : "From Config"}
									</Badge>
								)}
							</div>
							<p className="mt-0.5 text-muted-foreground text-xs font-mono truncate">
								{pkg.attr_path}
							</p>
							{pkg.description && (
								<p
									className={`text-muted-foreground line-clamp-2 ${isCompact ? "mt-1 text-xs" : "mt-2 text-sm"}`}
								>
									{pkg.description}
								</p>
							)}
							<div
								className={`flex items-center gap-2 flex-wrap ${isCompact ? "mt-1" : "mt-2"}`}
							>
								{pkg.license && (
									<Badge variant="outline" className="text-xs">
										{pkg.license}
									</Badge>
								)}
								{pkg.nixpkgs_url && (
									<a
										href={pkg.nixpkgs_url}
										target="_blank"
										rel="noopener noreferrer"
										className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-accent transition-colors"
										onClick={(e) => e.stopPropagation()}
									>
										<ExternalLink className="h-3 w-3" />
										Nixpkgs
									</a>
								)}
								{pkg.homepage && (
									<a
										href={pkg.homepage}
										target="_blank"
										rel="noopener noreferrer"
										className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-accent transition-colors"
										onClick={(e) => e.stopPropagation()}
									>
										<ExternalLink className="h-3 w-3" />
										Homepage
									</a>
								)}
							</div>
						</div>
					</div>
					<div className="flex items-center gap-2">
						{/* Remove button for user-installed packages */}
						{isUserInstalled && onRemove && (
							<TooltipProvider>
								<Tooltip>
									<TooltipTrigger asChild>
										<Button
											size="sm"
											variant="outline"
											className="shrink-0 cursor-pointer hover:text-destructive hover:border-destructive"
											onClick={() => onRemove(pkg)}
											disabled={isProcessing}
										>
											{isRemoving ? (
												<Loader2 className="h-4 w-4 animate-spin" />
											) : (
												<Trash2 className="h-4 w-4" />
											)}
										</Button>
									</TooltipTrigger>
									<TooltipContent>Remove from devshell</TooltipContent>
								</Tooltip>
							</TooltipProvider>
						)}
						{/* Add button for non-installed packages */}
						{onAdd && !isInstalled && (
							<TooltipProvider>
								<Tooltip>
									<TooltipTrigger asChild>
										<Button
											size="sm"
											variant="outline"
											className="shrink-0 cursor-pointer hover:text-accent-foreground"
											onClick={() => onAdd(pkg)}
											disabled={isProcessing}
										>
											{isAdding ? (
												<Loader2 className="h-4 w-4 animate-spin" />
											) : (
												<Plus className="h-4 w-4" />
											)}
										</Button>
									</TooltipTrigger>
									<TooltipContent>Add to devshell</TooltipContent>
								</Tooltip>
							</TooltipProvider>
						)}
					</div>
				</div>
			</CardContent>
		</Card>
	);
}
