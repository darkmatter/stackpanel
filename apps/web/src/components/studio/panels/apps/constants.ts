/**
 * App type configuration and helper functions
 */

export const APP_TYPES = [
	{ value: "bun", label: "Bun", color: "bg-yellow-500/20 text-yellow-400" },
	{ value: "node", label: "Node.js", color: "bg-green-500/20 text-green-400" },
	{ value: "go", label: "Go", color: "bg-cyan-500/20 text-cyan-400" },
	{ value: "python", label: "Python", color: "bg-blue-500/20 text-blue-400" },
	{ value: "rust", label: "Rust", color: "bg-orange-500/20 text-orange-400" },
	{ value: "other", label: "Other", color: "bg-gray-500/20 text-gray-400" },
] as const;

export type AppType = (typeof APP_TYPES)[number]["value"];

export function getTypeColor(type: string): string {
	return (
		APP_TYPES.find((t) => t.value === type)?.color ??
		"bg-gray-500/20 text-gray-400"
	);
}

export function getTypeLabel(type: string): string {
	return APP_TYPES.find((t) => t.value === type)?.label ?? type;
}
