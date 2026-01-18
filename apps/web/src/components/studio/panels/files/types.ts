/**
 * Type definitions for the files panel.
 */
import type { FileType } from "@stackpanel/proto";
import type { GeneratedFileWithStatus } from "@/lib/types";

export interface FileRowProps {
	file: GeneratedFileWithStatus;
	onPreview?: (file: GeneratedFileWithStatus) => void;
}

export interface SourceGroupProps {
	source: string;
	files: GeneratedFileWithStatus[];
	defaultExpanded?: boolean;
	onPreview?: (file: GeneratedFileWithStatus) => void;
}

export interface SummaryStatsProps {
	totalCount: number;
	enabledCount: number;
	staleCount: number;
	lastUpdated: string;
}

export interface PreviewModalProps {
	file: GeneratedFileWithStatus | null;
	onClose: () => void;
}

export interface FileTypeIconProps {
	type: FileType;
}

export interface FileStatusBadgeProps {
	file: GeneratedFileWithStatus;
}

export interface EmptyStateProps {
	onRefresh: () => void;
}
