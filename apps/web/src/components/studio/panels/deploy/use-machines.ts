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
// EC2 Provisioning Types — match aws-ec2-app Nix module
// =============================================================================

export interface Ec2MachineMeta {
	tags: string[];
	roles: string[];
	target_env: string | null;
	arch: string | null;
	ssh: MachineSSH;
}

export interface Ec2SecurityGroupRule {
	from_port: number;
	to_port: number;
	protocol: string;
	cidr_blocks: string[];
	description: string;
}

export interface Ec2SecurityGroup {
	create: boolean;
	name: string | null;
	description: string | null;
	ingress: Ec2SecurityGroupRule[];
	egress: Ec2SecurityGroupRule[];
}

export interface Ec2KeyPair {
	create: boolean;
	name: string | null;
	public_key: string | null;
}

export interface Ec2IamConfig {
	enable: boolean;
	role_name: string | null;
}

export interface Ec2AppInstance {
	name: string;
	ami: string | null;
	os_type: "ubuntu" | "nixos";
	instance_type: string | null;
	subnet_id: string | null;
	root_volume_size: number | null;
	associate_public_ip: boolean;
	tags: Record<string, string>;
	machine: Ec2MachineMeta;
}

export interface Ec2AppConfig {
	instance_count: number;
	instances: Ec2AppInstance[];
	ami: string | null;
	os_type: "ubuntu" | "nixos";
	instance_type: string | null;
	vpc_id: string | null;
	subnet_ids: string[];
	security_group_ids: string[];
	security_group: Ec2SecurityGroup;
	key_name: string | null;
	key_pair: Ec2KeyPair;
	iam: Ec2IamConfig;
	user_data: string | null;
	root_volume_size: number | null;
	associate_public_ip: boolean;
	tags: Record<string, string>;
	machine: Ec2MachineMeta;
}

export interface Ec2AppModuleConfig {
	enable: boolean;
	defaults: Partial<Ec2AppConfig>;
	apps: Record<string, Ec2AppConfig>;
}

export const DEFAULT_EC2_MACHINE_META: Ec2MachineMeta = {
	tags: [],
	roles: [],
	target_env: null,
	arch: null,
	ssh: { ...DEFAULT_SSH },
};

export const DEFAULT_EC2_APP: Ec2AppConfig = {
	instance_count: 1,
	instances: [],
	ami: null,
	os_type: "ubuntu",
	instance_type: "t3.micro",
	vpc_id: null,
	subnet_ids: [],
	security_group_ids: [],
	security_group: {
		create: true,
		name: null,
		description: null,
		ingress: [
			{ from_port: 22, to_port: 22, protocol: "tcp", cidr_blocks: ["0.0.0.0/0"], description: "SSH" },
			{ from_port: 80, to_port: 80, protocol: "tcp", cidr_blocks: ["0.0.0.0/0"], description: "HTTP" },
			{ from_port: 443, to_port: 443, protocol: "tcp", cidr_blocks: ["0.0.0.0/0"], description: "HTTPS" },
		],
		egress: [
			{ from_port: 0, to_port: 0, protocol: "-1", cidr_blocks: ["0.0.0.0/0"], description: "All outbound" },
		],
	},
	key_name: null,
	key_pair: { create: false, name: null, public_key: null },
	iam: { enable: true, role_name: null },
	user_data: null,
	root_volume_size: null,
	associate_public_ip: true,
	tags: {},
	machine: { ...DEFAULT_EC2_MACHINE_META },
};

const DEFAULT_EC2_MODULE: Ec2AppModuleConfig = {
	enable: false,
	defaults: {},
	apps: {},
};

// =============================================================================
// Hooks
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
		rawInfra,
		setInfra,
		addMachine,
		updateMachine,
		removeMachine,
		updateSettings,
		refetch,
	};
}

export function useEc2Provisioning() {
	const { data: rawInfra, mutate: setInfra, refetch } = useNixData<Record<string, unknown>>("infra");

	const config = useMemo<Ec2AppModuleConfig>(() => {
		if (!rawInfra) return DEFAULT_EC2_MODULE;
		const ec2App = (rawInfra as Record<string, unknown>)["aws_ec2_app"] as Partial<Ec2AppModuleConfig> | undefined;
		if (!ec2App) return DEFAULT_EC2_MODULE;
		return {
			enable: ec2App.enable ?? false,
			defaults: ec2App.defaults ?? {},
			apps: (ec2App.apps ?? {}) as Record<string, Ec2AppConfig>,
		};
	}, [rawInfra]);

	const saveConfig = async (newConfig: Ec2AppModuleConfig) => {
		const currentInfra = (rawInfra ?? {}) as Record<string, unknown>;
		await setInfra({
			...currentInfra,
			"aws_ec2_app": newConfig,
		} as any);
	};

	const addApp = async (key: string, app: Ec2AppConfig) => {
		const updated = { ...config };
		updated.apps = { ...updated.apps, [key]: app };
		if (!updated.enable) updated.enable = true;
		await saveConfig(updated);
	};

	const updateApp = async (key: string, app: Ec2AppConfig) => {
		const updated = { ...config };
		updated.apps = { ...updated.apps, [key]: app };
		await saveConfig(updated);
	};

	const removeApp = async (key: string) => {
		const updated = { ...config };
		const { [key]: _, ...rest } = updated.apps;
		updated.apps = rest;
		await saveConfig(updated);
	};

	const setEnabled = async (enabled: boolean) => {
		await saveConfig({ ...config, enable: enabled });
	};

	return {
		config,
		addApp,
		updateApp,
		removeApp,
		setEnabled,
		refetch,
	};
}
