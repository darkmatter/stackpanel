/**
 * Type definitions for the dev shells panel.
 */

export type ScriptValue = {
	exec?: string;
	command?: string;
	description?: string;
};

export type DevshellConfig = {
	hooks?: {
		before?: string[];
		main?: string[];
		after?: string[];
	};
	commands?: Record<string, ScriptValue | string>;
	_scripts?: Record<string, ScriptValue | string>;
	_tasks?: Record<string, ScriptValue | string>;
};

export type StackpanelConfigData = {
	devshell?: DevshellConfig;
	scripts?: Record<string, ScriptValue | string>;
};

export type AgentStatus = {
	status: string;
	devshell?: {
		in_devshell?: boolean;
		has_devshell_env?: boolean;
	};
};

export type ToolCategory = "language" | "runtime" | "tool";

export type AvailableTool = {
	id: string;
	name: string;
	version: string;
	category: ToolCategory;
};

export type DevShell = {
	name: string;
	description: string;
	languages: string[];
	tools: string[];
	hooks: string[];
	active: boolean;
};

export type Script = {
	name: string;
	description: string;
	exec: string;
};
