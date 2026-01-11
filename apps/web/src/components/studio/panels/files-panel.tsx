/**
 * Files Panel
 *
 * Displays generated files from stackpanel.files.entries.
 * Shows file metadata, staleness status, and allows regeneration.
 */

import { useState } from "react";
import {
  FileCode,
  FileText,
  Loader2,
  RefreshCw,
  Check,
  AlertTriangle,
  ChevronDown,
  ChevronRight,
  Eye,
  FolderOpen,
} from "lucide-react";
import { useGeneratedFiles } from "@/lib/use-generated-files";
import type { GeneratedFileWithStatus } from "@/lib/nix-client";
import { FileType } from "@stackpanel/proto";
import { cn } from "@/lib/utils";

// =============================================================================
// Source Display Names
// =============================================================================

const SOURCE_DISPLAY_NAMES: Record<string, string> = {
  ide: "IDE Integration",
  go: "Go Apps",
  bun: "Bun Apps",
  "process-compose": "Process Compose",
  unknown: "Other",
};

function getSourceDisplayName(source: string | null): string {
  if (!source) return SOURCE_DISPLAY_NAMES.unknown;
  return SOURCE_DISPLAY_NAMES[source] ?? source;
}

// =============================================================================
// Status Badge
// =============================================================================

function StatusBadge({ file }: { file: GeneratedFileWithStatus }) {
  if (!file.enable) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
        Disabled
      </span>
    );
  }

  if (!file.existsOnDisk) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-orange-500/10 px-2 py-0.5 text-xs text-orange-600 dark:text-orange-400">
        <AlertTriangle className="h-3 w-3" />
        Missing
      </span>
    );
  }

  if (file.isStale) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-yellow-500/10 px-2 py-0.5 text-xs text-yellow-600 dark:text-yellow-400">
        <AlertTriangle className="h-3 w-3" />
        Stale
      </span>
    );
  }

  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-green-500/10 px-2 py-0.5 text-xs text-green-600 dark:text-green-400">
      <Check className="h-3 w-3" />
      Up to date
    </span>
  );
}

// =============================================================================
// File Type Icon
// =============================================================================

function FileTypeIcon({ type }: { type: FileType }) {
  if (type === FileType.DERIVATION) {
    return <FileCode className="h-4 w-4 text-blue-500" />;
  }
  return <FileText className="h-4 w-4 text-muted-foreground" />;
}

// =============================================================================
// File Row
// =============================================================================

interface FileRowProps {
  file: GeneratedFileWithStatus;
  onPreview?: (file: GeneratedFileWithStatus) => void;
}

function FileRow({ file, onPreview }: FileRowProps) {
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
            <StatusBadge file={file} />
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

interface SourceGroupProps {
  source: string;
  files: GeneratedFileWithStatus[];
  defaultExpanded?: boolean;
  onPreview?: (file: GeneratedFileWithStatus) => void;
}

function SourceGroup({
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

interface SummaryStatsProps {
  totalCount: number;
  enabledCount: number;
  staleCount: number;
  lastUpdated: string;
}

function SummaryStats({
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
// Preview Modal (placeholder for future implementation)
// =============================================================================

interface PreviewModalProps {
  file: GeneratedFileWithStatus | null;
  onClose: () => void;
}

function PreviewModal({ file, onClose }: PreviewModalProps) {
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
// Helpers
// =============================================================================

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatRelativeTime(isoString: string): string {
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);

  if (diffSec < 60) return "just now";
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
  return date.toLocaleDateString();
}

// =============================================================================
// Main Component
// =============================================================================

export function FilesPanel() {
  const {
    data,
    isLoading,
    isError,
    error,
    refetch,
    filesBySource,
    staleFiles,
  } = useGeneratedFiles();

  const [previewFile, setPreviewFile] =
    useState<GeneratedFileWithStatus | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefetch = async () => {
    setIsRefreshing(true);
    try {
      await refetch();
    } finally {
      setIsRefreshing(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex min-h-[400px] items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex min-h-[400px] flex-col items-center justify-center gap-4">
        <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
          <p className="text-sm text-destructive">
            Failed to load generated files: {error?.message ?? "Unknown error"}
          </p>
        </div>
        <button
          type="button"
          onClick={handleRefetch}
          className="text-sm text-primary underline-offset-4 hover:underline"
        >
          Try again
        </button>
      </div>
    );
  }

  if (!data || data.totalCount === 0) {
    return <EmptyState onRefresh={handleRefetch} />;
  }

  // Sort sources: known sources first, then alphabetically
  const sortedSources = Object.keys(filesBySource).sort((a, b) => {
    const aKnown = a in SOURCE_DISPLAY_NAMES;
    const bKnown = b in SOURCE_DISPLAY_NAMES;
    if (aKnown && !bKnown) return -1;
    if (!aKnown && bKnown) return 1;
    return getSourceDisplayName(a).localeCompare(getSourceDisplayName(b));
  });

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <FileCode className="h-6 w-6" />
            Generated Files
          </h1>
          <p className="text-muted-foreground">
            Files generated by stackpanel.files.entries
          </p>
        </div>
        <button
          type="button"
          onClick={handleRefetch}
          disabled={isRefreshing}
          className="inline-flex items-center gap-2 rounded-md border bg-background px-3 py-2 text-sm font-medium transition-colors hover:bg-accent disabled:opacity-50"
        >
          <RefreshCw
            className={cn("h-4 w-4", isRefreshing && "animate-spin")}
          />
          {isRefreshing ? "Refreshing..." : "Refresh"}
        </button>
      </div>

      {/* Summary */}
      <div className="rounded-lg border bg-card p-4">
        <SummaryStats
          totalCount={data.totalCount}
          enabledCount={data.enabledCount}
          staleCount={data.staleCount}
          lastUpdated={data.lastUpdated}
        />
      </div>

      {/* Stale files warning */}
      {staleFiles.length > 0 && (
        <div className="rounded-lg border border-yellow-500/30 bg-yellow-500/5 p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-yellow-500" />
            <div className="space-y-1">
              <p className="font-medium text-yellow-600 dark:text-yellow-400">
                {staleFiles.length} file{staleFiles.length !== 1 ? "s" : ""}{" "}
                need regeneration
              </p>
              <p className="text-sm text-muted-foreground">
                Run <code className="rounded bg-muted px-1">write-files</code>{" "}
                in your devshell to update them.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* File groups */}
      <div className="space-y-4">
        {sortedSources.map((source) => (
          <SourceGroup
            key={source}
            source={source}
            files={filesBySource[source]}
            onPreview={setPreviewFile}
          />
        ))}
      </div>

      {/* Preview modal */}
      <PreviewModal file={previewFile} onClose={() => setPreviewFile(null)} />
    </div>
  );
}

// =============================================================================
// Empty State
// =============================================================================

function EmptyState({ onRefresh }: { onRefresh: () => void }) {
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
