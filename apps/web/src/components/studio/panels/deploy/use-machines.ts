"use client";

import { useMemo } from "react";
import { useNixData } from "@/lib/use-agent";

// =============================================================================
// Types — match the Nix module schema (nix/stackpanel/infra/modules/machines)
// =============================================================================

export interface MachineSSH {
	user: string;
	port: number;
	key_path: string | null;
}

export interface MachineConfig {
	id?: string | null;
	name: string | null;
	host: string | null;
	ssh: MachineSSH;
	tags: string[];
	roles: string[];
	provider: string | null;
	arch: string | null;
	public_ip: string | null;
	private_ip: string | null;
	target_env: string | null;
	labels: Record<string, string>;
	nixos_profile: string | null;
	nixos_modules: string[];
	env: Record<string, string>;
	metadata: Record<string, unknown>;
}

export interface AwsFilter {
	name: string;
	values: string[];
}

export interface AwsMachinesConfig {
	region: string | null;
	instance_ids: string[];
	filters: AwsFilter[];
	name_tag_keys: string[];
	role_tag_keys: string[];
	tag_keys: string[];
	env_tag_keys: string[];
	host_preference: string[];
	ssh: MachineSSH;
}

export interface MachinesModuleConfig {
	enable: boolean;
	source: "static" | "aws-ec2";
	aws: AwsMachinesConfig;
	machines: Record<string, MachineConfig>;
}

// =============================================================================
// Defaults
// =============================================================================

export const DEFAULT_SSH: MachineSSH = {
	user: "root",
	port: 22,
	key_path: null,
};

export const DEFAULT_MACHINE: MachineConfig = {
	id: null,
	name: null,
	host: null,
	ssh: { ...DEFAULT_SSH },
	tags: [],
	roles: [],
	provider: null,
	arch: null,
	public_ip: null,
	private_ip: null,
	target_env: null,
	labels: {},
	nixos_profile: null,
	nixos_modules: [],
	env: {},
	metadata: {},
};

const DEFAULT_AWS_CONFIG: AwsMachinesConfig = {
	region: null,
	instance_ids: [],
	filters: [{ name: "instance-state-name", values: ["running"] }],
	name_tag_keys: ["Name"],
	role_tag_keys: ["stackpanel:role", "role"],
	tag_keys: ["stackpanel:tag", "tag"],
	env_tag_keys: ["stackpanel:env", "env", "stage"],
	host_preference: ["publicDns", "publicIp", "privateIp"],
	ssh: { ...DEFAULT_SSH },
};

const DEFAULT_CONFIG: MachinesModuleConfig = {
	enable: false,
	source: "static",
	aws: DEFAULT_AWS_CONFIG,
	machines: {},
};

// =============================================================================
// Hook
// =============================================================================

export function useMachinesConfig() {
	const { data: rawInfra, mutate: setInfra, refetch } = useNixData<Record<string, unknown>>("infra");

	const config = useMemo<MachinesModuleConfig>(() => {
		if (!rawInfra) return DEFAULT_CONFIG;
		const machines = (rawInfra as Record<string, unknown>).machines as Partial<MachinesModuleConfig> | undefined;
		if (!machines) return DEFAULT_CONFIG;
		return {
			enable: machines.enable ?? false,
			source: machines.source ?? "static",
			aws: {
				...DEFAULT_AWS_CONFIG,
				...(machines.aws ?? {}),
			},
			machines: (machines.machines ?? {}) as Record<string, MachineConfig>,
		};
	}, [rawInfra]);

	const saveConfig = async (newConfig: MachinesModuleConfig) => {
		const currentInfra = (rawInfra ?? {}) as Record<string, unknown>;
		await setInfra({
			...currentInfra,
			machines: newConfig,
		} as any);
	};

	const addMachine = async (key: string, machine: MachineConfig) => {
		const updated = { ...config };
		updated.machines = { ...updated.machines, [key]: machine };
		if (!updated.enable) updated.enable = true;
		await saveConfig(updated);
	};

	const updateMachine = async (key: string, machine: MachineConfig) => {
		const updated = { ...config };
		updated.machines = { ...updated.machines, [key]: machine };
		await saveConfig(updated);
	};

	const removeMachine = async (key: string) => {
		const updated = { ...config };
		const { [key]: _, ...rest } = updated.machines;
		updated.machines = rest;
		await saveConfig(updated);
	};

	const updateSettings = async (settings: Partial<MachinesModuleConfig>) => {
		await saveConfig({ ...config, ...settings });
	};

	return {
		config,
		addMachine,
		updateMachine,
		removeMachine,
		updateSettings,
		refetch,
	};
}
