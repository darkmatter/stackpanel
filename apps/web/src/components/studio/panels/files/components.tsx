/**
 * Reusable components for the Files Panel
 */

import {
	AlertTriangle,
	Check,
	ChevronDown,
	ChevronRight,
	Eye,
	FileCode,
	FileText,
	FolderOpen,
	RefreshCw,
} from "lucide-react";
import { useState } from "react";
import { FileType } from "@stackpanel/proto";
import { StatusBadge } from "@/components/ui/status-badge";
import { cn } from "@/lib/utils";
// GeneratedFileWithStatus type from @/lib/types used in ./types
import type {
	FileRowProps,
	SourceGroupProps,
	SummaryStatsProps,
	PreviewModalProps,
	FileStatusBadgeProps,
	FileTypeIconProps,
	EmptyStateProps,
} from "./types";
import {
	formatFileSize,
	formatRelativeTime,
	getSourceDisplayName,
} from "./constants";

// =============================================================================
// File Status Badge
// =============================================================================

export function FileStatusBadge({ file }: FileStatusBadgeProps) {
	if (!file.enable) {
		return <StatusBadge status="fileDisabled" />;
	}

	if (!file.existsOnDisk) {
		return <StatusBadge status="fileMissing" />;
	}

	if (file.isStale) {
		return <StatusBadge status="fileStale" />;
	}

	return <StatusBadge status={{ text: "Up to date", variant: "success" }} />;
}

// =============================================================================
// File Type Icon
// =============================================================================

export function FileTypeIcon({ type }: FileTypeIconProps) {
	if (type === FileType.DERIVATION) {
		return <FileCode className="h-4 w-4 text-blue-500" />;
	}
	return <FileText className="h-4 w-4 text-muted-foreground" />;
}

// =============================================================================
// File Row
// =============================================================================

export function FileRow({ file, onPreview }: FileRowProps) {
	const fileName = file.path.split("/").pop() ?? file.path;
	const directory = file.path.includes("/")
		? file.path.substring(0, file.path.lastIndexOf("/"))
		: "";

	return (
		<div
			className={cn(
				"group flex items-center justify-between rounded-md border px-3 py-2 transition-colors",
				file.isStale && file.enable
					? "border-yellow-500/30 bg-yellow-500/5"
					: "border-border bg-card hover:bg-accent/50",
			)}
		>
			<div className="flex min-w-0 flex-1 items-center gap-3">
				<FileTypeIcon type={file.type} />
				<div className="min-w-0 flex-1">
					<div className="flex items-center gap-2">
						<span className="truncate font-mono text-sm">{fileName}</span>
						<FileStatusBadge file={file} />
					</div>
					{directory && (
						<div className="flex items-center gap-1 text-xs text-muted-foreground">
							<FolderOpen className="h-3 w-3" />
							<span className="truncate">{directory}</span>
						</div>
					)}
					{file.description && (
						<p className="mt-0.5 truncate text-xs text-muted-foreground">
							{file.description}
						</p>
					)}
				</div>
			</div>

			<div className="flex items-center gap-2">
				{file.size !== null && (
					<span className="text-xs text-muted-foreground">
						{formatFileSize(file.size)}
					</span>
				)}
				{onPreview && (
					<button
						type="button"
						onClick={() => onPreview(file)}
						className="rounded p-1 opacity-0 transition-opacity hover:bg-accent group-hover:opacity-100"
						title="Preview file"
					>
						<Eye className="h-4 w-4 text-muted-foreground" />
					</button>
				)}
			</div>
		</div>
	);
}

// =============================================================================
// Source Group
// =============================================================================

export function SourceGroup({
	source,
	files,
	defaultExpanded = true,
	onPreview,
}: SourceGroupProps) {
	const [expanded, setExpanded] = useState(defaultExpanded);

	const staleCount = files.filter((f) => f.isStale && f.enable).length;
	const enabledCount = files.filter((f) => f.enable).length;

	return (
		<div className="space-y-2">
			<button
				type="button"
				onClick={() => setExpanded(!expanded)}
				className="flex w-full items-center gap-2 rounded-md px-2 py-1 text-left transition-colors hover:bg-accent"
			>
				{expanded ? (
					<ChevronDown className="h-4 w-4 text-muted-foreground" />
				) : (
					<ChevronRight className="h-4 w-4 text-muted-foreground" />
				)}
				<span className="font-medium">{getSourceDisplayName(source)}</span>
				<span className="text-sm text-muted-foreground">
					({enabledCount} file{enabledCount !== 1 ? "s" : ""})
				</span>
				{staleCount > 0 && (
					<span className="rounded-full bg-yellow-500/10 px-2 py-0.5 text-xs text-yellow-600 dark:text-yellow-400">
						{staleCount} stale
					</span>
				)}
			</button>

			{expanded && (
				<div className="ml-6 space-y-1">
					{files.map((file) => (
						<FileRow key={file.path} file={file} onPreview={onPreview} />
					))}
				</div>
			)}
		</div>
	);
}

// =============================================================================
// Summary Stats
// =============================================================================

export function SummaryStats({
	totalCount,
	enabledCount,
	staleCount,
	lastUpdated,
}: SummaryStatsProps) {
	const upToDateCount = enabledCount - staleCount;

	return (
		<div className="flex flex-wrap items-center gap-4 text-sm">
			<div className="flex items-center gap-2">
				<span className="text-muted-foreground">Total:</span>
				<span className="font-medium">{totalCount} files</span>
			</div>
			<div className="flex items-center gap-2">
				<Check className="h-4 w-4 text-green-500" />
				<span>{upToDateCount} up to date</span>
			</div>
			{staleCount > 0 && (
				<div className="flex items-center gap-2">
					<AlertTriangle className="h-4 w-4 text-yellow-500" />
					<span className="text-yellow-600 dark:text-yellow-400">
						{staleCount} stale
					</span>
				</div>
			)}
			<div className="ml-auto text-xs text-muted-foreground">
				Updated: {formatRelativeTime(lastUpdated)}
			</div>
		</div>
	);
}

// =============================================================================
// Preview Modal
// =============================================================================

export function PreviewModal({ file, onClose }: PreviewModalProps) {
	if (!file) return null;

	return (
		<div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
			<div className="max-h-[80vh] w-full max-w-2xl overflow-hidden rounded-lg border bg-background shadow-lg">
				<div className="flex items-center justify-between border-b px-4 py-3">
					<div className="flex items-center gap-2">
						<FileTypeIcon type={file.type} />
						<span className="font-mono text-sm">{file.path}</span>
					</div>
					<button
						type="button"
						onClick={onClose}
						className="rounded p-1 hover:bg-accent"
					>
						×
					</button>
				</div>
				<div className="overflow-auto p-4">
					<div className="space-y-2 text-sm">
						<div className="flex gap-2">
							<span className="text-muted-foreground">Type:</span>
							<span>{file.type}</span>
						</div>
						{file.source && (
							<div className="flex gap-2">
								<span className="text-muted-foreground">Source:</span>
								<span>{getSourceDisplayName(file.source)}</span>
							</div>
						)}
						{file.description && (
							<div className="flex gap-2">
								<span className="text-muted-foreground">Description:</span>
								<span>{file.description}</span>
							</div>
						)}
						{file.mode && (
							<div className="flex gap-2">
								<span className="text-muted-foreground">Mode:</span>
								<span className="font-mono">{file.mode}</span>
							</div>
						)}
						{file.store_path && (
							<div className="flex gap-2">
								<span className="text-muted-foreground">Store path:</span>
								<span className="truncate font-mono text-xs">
									{file.store_path}
								</span>
							</div>
						)}
					</div>
					<div className="mt-4 rounded border bg-muted/30 p-4 text-center text-sm text-muted-foreground">
						Content preview coming soon
					</div>
				</div>
			</div>
		</div>
	);
}

// =============================================================================
// Empty State
// =============================================================================

export function EmptyState({ onRefresh }: EmptyStateProps) {
	return (
		<div className="flex min-h-[400px] flex-col items-center justify-center gap-4">
			<FileCode className="h-16 w-16 text-muted-foreground/50" />
			<div className="text-center">
				<h2 className="text-xl font-semibold">No Generated Files</h2>
				<p className="mt-1 text-sm text-muted-foreground">
					Files declared in stackpanel.files.entries will appear here.
				</p>
				<p className="mt-2 text-xs text-muted-foreground">
					Add file entries in your Nix modules using{" "}
					<code className="rounded bg-muted px-1 py-0.5">
						stackpanel.files.entries
					</code>
				</p>
			</div>
			<button
				type="button"
				onClick={onRefresh}
				className="mt-2 inline-flex items-center gap-2 rounded-md border bg-background px-3 py-2 text-sm font-medium transition-colors hover:bg-accent"
			>
				<RefreshCw className="h-4 w-4" />
				Refresh
			</button>
		</div>
	);
}
