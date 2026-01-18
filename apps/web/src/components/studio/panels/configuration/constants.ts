/**
 * Constants and helpers for the configuration panel.
 */

export const STARSHIP_PRESETS = [
	{ value: "stackpanel", label: "Stackpanel (Custom)" },
	{ value: "starship-default", label: "Starship Default" },
] as const;

/**
 * Returns the trimmed value if non-empty, otherwise undefined.
 * Used for optional form fields.
 */
export function optionalValue(value: string): string | undefined {
	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : undefined;
}
