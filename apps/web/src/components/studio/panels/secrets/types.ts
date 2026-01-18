/**
 * Type definitions for the secrets panel.
 */

export interface Secret {
	key: string;
	value?: string;
	environment: string;
	type?: string;
}

export interface SecretsPanelState {
	searchQuery: string;
	dialogOpen: boolean;
	selectedEnvironment: string;
	newSecretKey: string;
	newSecretValue: string;
	showSecret: string | null;
	secrets: Secret[];
	secretValues: Record<string, string>;
	isLoading: boolean;
	isSaving: boolean;
	error: string | null;
}
