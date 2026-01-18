/**
 * Type definitions for the app config drawer.
 */

export type Environment = "development" | "staging" | "production";

export type AvailableTask = {
	name: string;
	defaultScript: string;
	description?: string;
};

export type TaskConfig = {
	key: string;
	command: string;
};

export type AvailableSecret = {
	id: string;
	name: string;
	type: "secret" | "variable";
	value?: string; // Only for non-secrets
};

export type VariableConfig = {
	secretId: string;
	environments: Environment[];
};

export type App = {
	id: string;
	name: string;
	badge?: string;
	path: string;
	domain: string;
	tasks: { name: string; description: string }[];
	variables: { name: string; type: "secret" | "variable"; computed: boolean }[];
};

export interface AppConfigDrawerProps {
	app: App | null;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}
