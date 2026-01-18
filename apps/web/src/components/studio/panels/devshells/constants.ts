/**
 * Constants and helper functions for the dev shells panel.
 */
import type { ToolCategory } from "./types";

export const RUNTIME_KEYWORDS = ["node", "nodejs", "bun", "deno"];

export const LANGUAGE_KEYWORDS = [
	"python",
	"go",
	"rust",
	"ruby",
	"java",
	"kotlin",
	"swift",
	"zig",
	"dotnet",
	"clang",
	"gcc",
	"php",
	"julia",
];

export function categorizePackage(name: string): ToolCategory {
	const normalized = name.toLowerCase();
	if (RUNTIME_KEYWORDS.some((keyword) => normalized.includes(keyword))) {
		return "runtime";
	}
	if (LANGUAGE_KEYWORDS.some((keyword) => normalized.includes(keyword))) {
		return "language";
	}
	return "tool";
}

export function formatPackageLabel(name: string, version?: string): string {
	return version ? `${name} ${version}` : name;
}
