/**
 * Variable type configuration and helper functions
 */

import { VariableType } from "@stackpanel/proto";
import { Key, Server, Settings, Sparkles } from "lucide-react";

export const VARIABLE_TYPES = [
	{
		value: "secret",
		label: "Secret",
		description: "Sensitive value stored encrypted",
		icon: Key,
		color: "bg-red-500/20 text-red-400",
		readonly: false,
	},
	{
		value: "config",
		label: "Config",
		description: "Non-sensitive configuration",
		icon: Settings,
		color: "bg-blue-500/20 text-blue-400",
		readonly: false,
	},
	{
		value: "computed",
		label: "Computed",
		description: "Derived from other config",
		icon: Sparkles,
		color: "bg-purple-500/20 text-purple-400",
		readonly: true,
	},
	{
		value: "service",
		label: "Service",
		description: "Auto-generated from service",
		icon: Server,
		color: "bg-green-500/20 text-green-400",
		readonly: true,
	},
] as const;

export type VariableTypeName = (typeof VARIABLE_TYPES)[number]["value"];

/** Map proto VariableType enum to UI type string */
function variableTypeToString(type: VariableType | string | number): string {
	// Handle string types (from Nix data, may be uppercase)
	if (typeof type === "string") {
		const lower = type.toLowerCase();
		// Map common string values to our type names
		if (lower === "secret") return "secret";
		if (lower === "variable" || lower === "config") return "config";
		if (lower === "vals" || lower === "computed") return "computed";
		if (lower === "service") return "service";
		return "config"; // Default
	}
	// Handle numeric enum values
	switch (type) {
		case VariableType.SECRET:
		case 1:
			return "secret";
		case VariableType.VARIABLE:
		case 0:
			return "config";
		case VariableType.VALS:
		case 2:
			return "computed";
		default:
			return "config";
	}
}

export function getTypeConfig(type: VariableType | string) {
	const typeStr = variableTypeToString(type);
	return VARIABLE_TYPES.find((t) => t.value === typeStr) ?? VARIABLE_TYPES[1];
}
