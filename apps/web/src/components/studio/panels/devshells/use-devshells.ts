/**
 * Hook for managing dev shells panel state.
 */
import { useEffect, useMemo, useState } from "react";
import { useAgentContext } from "@/lib/agent-provider";
import { useInstalledPackages } from "@/lib/use-installed-packages";
import { useNixConfig } from "@/lib/use-nix-config";
import { categorizePackage, formatPackageLabel } from "./constants";
import type {
	AgentStatus,
	AvailableTool,
	DevShell,
	Script,
	StackpanelConfigData,
} from "./types";

export function useDevShells() {
	const { host, port, healthStatus, token } = useAgentContext();
	const { data: config } = useNixConfig();
	const { packages: installedPackages } = useInstalledPackages({ host, port });
	const [dialogOpen, setDialogOpen] = useState(false);
	const [activeTab, setActiveTab] = useState("shells");
	const [agentStatus, setAgentStatus] = useState<AgentStatus | null>(null);
	const [visibleItems, setVisibleItems] = useState<number>(24);

	useEffect(() => {
		let isMounted = true;
		const fetchStatus = async () => {
			try {
				const response = await fetch(`http://${host}:${port}/status`);
				if (!response.ok) return;
				const data = (await response.json()) as AgentStatus;
				if (isMounted) {
					setAgentStatus(data);
				}
			} catch {
				if (isMounted) {
					setAgentStatus(null);
				}
			}
		};
		fetchStatus();
		const interval = setInterval(fetchStatus, 5000);
		return () => {
			isMounted = false;
			clearInterval(interval);
		};
	}, [host, port]);

	const stackpanelConfig = useMemo(() => {
		if (!config || typeof config !== "object")
			return {} as StackpanelConfigData;
		const maybeStackpanel = (config as { stackpanel?: unknown }).stackpanel;
		if (maybeStackpanel && typeof maybeStackpanel === "object") {
			return maybeStackpanel as StackpanelConfigData;
		}
		return config as StackpanelConfigData;
	}, [config]);

	const devshellConfig = stackpanelConfig.devshell ?? {};

	const hookBadges = useMemo(() => {
		const hooks = devshellConfig.hooks;
		if (!hooks) return [] as string[];
		const entries: Array<[string, string[]]> = [
			["before", hooks.before ?? []],
			["main", hooks.main ?? []],
			["after", hooks.after ?? []],
		];
		return entries
			.filter(([, items]) => items.length > 0)
			.map(([label, items]) => `${label} (${items.length})`);
	}, [devshellConfig.hooks]);

	const availableTools = useMemo<AvailableTool[]>(() => {
		const byKey = new Map<string, AvailableTool>();
		for (const pkg of installedPackages) {
			const key = pkg.attrPath || pkg.name;
			if (!key || byKey.has(key)) continue;
			const name = pkg.name || key;
			byKey.set(key, {
				id: key,
				name,
				version: pkg.version ?? "",
				category: categorizePackage(name),
			});
		}
		return Array.from(byKey.values());
	}, [installedPackages]);

	const languageLabels = useMemo(
		() =>
			availableTools
				.filter((tool) => tool.category !== "tool")
				.map((tool) => formatPackageLabel(tool.name, tool.version)),
		[availableTools],
	);

	const toolLabels = useMemo(
		() =>
			availableTools
				.filter((tool) => tool.category === "tool")
				.map((tool) => formatPackageLabel(tool.name, tool.version)),
		[availableTools],
	);

	const scripts = useMemo<Script[]>(() => {
		const sources: Array<
			Record<string, { exec?: string; command?: string } | string> | undefined
		> = [
			stackpanelConfig.scripts,
			devshellConfig.commands,
			devshellConfig._scripts,
			devshellConfig._tasks,
		];
		const collected = new Map<string, string>();
		for (const source of sources) {
			if (!source) continue;
			for (const [name, value] of Object.entries(source)) {
				if (collected.has(name)) continue;
				if (typeof value === "string") {
					collected.set(name, value);
					continue;
				}
				const description = value.exec ?? value.command;
				collected.set(name, description ?? "Defined in stackpanel config");
			}
		}
		return Array.from(collected, ([name, description]) => ({
			name,
			description,
		}));
	}, [stackpanelConfig.scripts, devshellConfig]);

	const devShells = useMemo<DevShell[]>(() => {
		if (
			availableTools.length === 0 &&
			hookBadges.length === 0 &&
			scripts.length === 0
		) {
			return [];
		}
		return [
			{
				name: "default",
				description: "Stackpanel devshell configuration",
				languages: languageLabels,
				tools: toolLabels,
				hooks: hookBadges,
				active: Boolean(
					agentStatus?.devshell?.in_devshell ||
						agentStatus?.devshell?.has_devshell_env,
				),
			},
		];
	}, [
		availableTools,
		agentStatus?.devshell?.has_devshell_env,
		agentStatus?.devshell?.in_devshell,
		hookBadges,
		languageLabels,
		scripts,
		toolLabels,
	]);

	return {
		// UI state
		dialogOpen,
		setDialogOpen,
		activeTab,
		setActiveTab,
		visibleItems,
		setVisibleItems,

		// Agent state
		healthStatus,
		token,
		agentStatus,

		// Data
		availableTools,
		scripts,
		devShells,
	};
}
