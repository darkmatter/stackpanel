/**
 * Constants and helpers for the files panel.
 */

// =============================================================================
// Source Display Names
// =============================================================================

export const SOURCE_DISPLAY_NAMES: Record<string, string> = {
	ide: "IDE Integration",
	go: "Go Apps",
	bun: "Bun Apps",
	"process-compose": "Process Compose",
	unknown: "Other",
};

export function getSourceDisplayName(source: string | null): string {
	if (!source) return SOURCE_DISPLAY_NAMES.unknown;
	return SOURCE_DISPLAY_NAMES[source] ?? source;
}

// =============================================================================
// File Helpers
// =============================================================================

export function formatFileSize(bytes: number): string {
	if (bytes < 1024) return `${bytes} B`;
	if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
	return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatRelativeTime(isoString: string): string {
	const date = new Date(isoString);
	const now = new Date();
	const diffMs = now.getTime() - date.getTime();
	const diffSec = Math.floor(diffMs / 1000);

	if (diffSec < 60) return "just now";
	if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
	if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
	return date.toLocaleDateString();
}

/**
 * Sort sources: known sources first, then alphabetically
 */
export function sortSources(sources: string[]): string[] {
	return sources.sort((a, b) => {
		const aKnown = a in SOURCE_DISPLAY_NAMES;
		const bKnown = b in SOURCE_DISPLAY_NAMES;
		if (aKnown && !bKnown) return -1;
		if (!aKnown && bKnown) return 1;
		return getSourceDisplayName(a).localeCompare(getSourceDisplayName(b));
	});
}
