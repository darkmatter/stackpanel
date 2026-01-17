/**
 * Auto-generated TypeScript types from Go types.
 * DO NOT EDIT MANUALLY - regenerate with:
 *   cd packages/stackpanel-go && ./types/gen.sh
 *
 * Source: packages/stackpanel-go/types/types.go
 */

/**
 * Stackpanel configuration produced by Nix evaluation
 */
export interface StackpanelConfig {
	apps: { [key: string]: AppValue };
	basePort: number;
	error?: string;
	hint?: string;
	motd?: Motd;
	network: Network;
	paths: Paths;
	projectName: string;
	projectRoot?: string;
	services: { [key: string]: ServiceValue };
	version: number;
}

export interface AppValue {
	domain?: string;
	port: number;
	tls: boolean;
	url?: string;
}

export interface Motd {
	commands?: CommandElement[];
	enable: boolean;
	features?: string[];
	hints?: string[];
}

export interface CommandElement {
	description: string;
	name: string;
}

export interface Network {
	step: Step;
}

export interface Step {
	caUrl?: string;
	enable: boolean;
}

export interface Paths {
	data: string;
	gen: string;
	state: string;
}

export interface ServiceValue {
	envVar: string;
	key: string;
	name: string;
	port: number;
}
