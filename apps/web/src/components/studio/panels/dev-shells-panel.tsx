"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Checkbox } from "@ui/checkbox";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import {
	AlertTriangle,
	Code,
	FileCode,
	GitBranch,
	Loader2,
	Package,
	Play,
	Plus,
	Terminal,
} from "lucide-react";
import { use, useEffect, useMemo, useState } from "react";
import { useAgentContext } from "@/lib/agent-provider";
import { useInstalledPackages } from "@/lib/use-installed-packages";
import { useNixConfig } from "@/lib/use-nix-config";

const runtimeKeywords = ["node", "nodejs", "bun", "deno"];
const languageKeywords = [
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

function categorizePackage(name: string): "language" | "runtime" | "tool" {
	const normalized = name.toLowerCase();
	if (runtimeKeywords.some((keyword) => normalized.includes(keyword))) {
		return "runtime";
	}
	if (languageKeywords.some((keyword) => normalized.includes(keyword))) {
		return "language";
	}
	return "tool";
}

function formatPackageLabel(name: string, version?: string) {
	return version ? `${name} ${version}` : name;
}

type DevshellConfig = {
	hooks?: {
		before?: string[];
		main?: string[];
		after?: string[];
	};
	commands?: Record<string, { exec?: string; command?: string } | string>;
	_scripts?: Record<string, { exec?: string; command?: string } | string>;
	_tasks?: Record<string, { exec?: string; command?: string } | string>;
};

type StackpanelConfigData = {
	devshell?: DevshellConfig;
	scripts?: Record<string, { exec?: string; command?: string } | string>;
};

type AgentStatus = {
	status: string;
	devshell?: {
		in_devshell?: boolean;
		has_devshell_env?: boolean;
	};
};

export function DevShellsPanel() {
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

	const availableTools = useMemo(() => {
		const byKey = new Map<
			string,
			{
				id: string;
				name: string;
				version: string;
				category: "language" | "runtime" | "tool";
			}
		>();
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

	const scripts = useMemo(() => {
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

	const devShells = useMemo(() => {
		if (
			availableTools.length === 0 &&
			hookBadges.length === 0 &&
			scripts.length === 0
		) {
			return [] as Array<{
				name: string;
				description: string;
				languages: string[];
				tools: string[];
				hooks: string[];
				active: boolean;
			}>;
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

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h2 className="font-semibold text-foreground text-xl">Dev Shells</h2>
					<p className="text-muted-foreground text-sm">
						Nix-based development environments powered by devenv
					</p>
				</div>
				<Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
					<DialogTrigger asChild>
						<Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
							<Plus className="h-4 w-4" />
							Create Shell
						</Button>
					</DialogTrigger>
					<DialogContent className="max-w-2xl">
						<DialogHeader>
							<DialogTitle>Create Dev Shell</DialogTitle>
							<DialogDescription>
								Configure a new Nix development environment for your team.
							</DialogDescription>
						</DialogHeader>
						<div className="grid gap-4 py-4">
							<div className="grid gap-2">
								<Label htmlFor="shell-name">Shell Name</Label>
								<Input id="shell-name" placeholder="my-shell" />
							</div>
							<div className="grid gap-2">
								<Label>Languages & Runtimes</Label>
								<div className="grid grid-cols-3 gap-2">
									{availableTools
										.filter(
											(t) =>
												t.category === "language" || t.category === "runtime",
										)
										.map((tool) => (
											<label
												className="flex cursor-pointer items-center gap-2 rounded-lg border border-border p-3 hover:bg-secondary/50"
												key={tool.id}
											>
												<Checkbox id={tool.id} />
												<div className="text-sm">
													<p className="font-medium text-foreground">
														{tool.name}
													</p>
													<p className="text-muted-foreground text-xs">
														{tool.version}
													</p>
												</div>
											</label>
										))}
								</div>
							</div>
							<div className="grid gap-2">
								<Label>Git Hooks</Label>
								<div className="flex gap-4">
									<label className="flex items-center gap-2">
										<Checkbox id="pre-commit" />
										<span className="text-sm">pre-commit</span>
									</label>
									<label className="flex items-center gap-2">
										<Checkbox id="commit-msg" />
										<span className="text-sm">commit-msg</span>
									</label>
									<label className="flex items-center gap-2">
										<Checkbox id="pre-push" />
										<span className="text-sm">pre-push</span>
									</label>
								</div>
							</div>
						</div>
						<DialogFooter>
							<Button onClick={() => setDialogOpen(false)} variant="outline">
								Cancel
							</Button>
							<Button className="bg-accent text-accent-foreground hover:bg-accent/90">
								Create Shell
							</Button>
						</DialogFooter>
					</DialogContent>
				</Dialog>
			</div>

			<Tabs onValueChange={setActiveTab} value={activeTab}>
				<TabsList>
					<TabsTrigger value="shells">Shells</TabsTrigger>
					<TabsTrigger value="tools">Available Tools</TabsTrigger>
					<TabsTrigger value="scripts">Scripts</TabsTrigger>
				</TabsList>

				<TabsContent className="mt-6 space-y-4" value="shells">
					{healthStatus === "checking" && (
						<Card>
							<CardContent className="flex items-center gap-2 p-4 text-muted-foreground text-sm">
								<Loader2 className="h-4 w-4 animate-spin" />
								Checking agent status...
							</CardContent>
						</Card>
					)}
					{healthStatus === "unavailable" && (
						<Card className="border-amber-500/40 bg-amber-500/10">
							<CardContent className="flex items-center gap-2 p-4 text-amber-600 text-sm dark:text-amber-400">
								<AlertTriangle className="h-4 w-4" />
								Agent unavailable. Start the agent to load devshell data.
							</CardContent>
						</Card>
					)}
					{healthStatus === "available" && !token && (
						<Card className="border-amber-500/40 bg-amber-500/10">
							<CardContent className="flex items-center gap-2 p-4 text-amber-600 text-sm dark:text-amber-400">
								<AlertTriangle className="h-4 w-4" />
								Pair with the agent to load devshell data.
							</CardContent>
						</Card>
					)}
					{devShells.length === 0 ? (
						<Card>
							<CardContent className="p-6">
								<p className="text-muted-foreground text-sm">
									Connect to the agent to load devshell details.
								</p>
							</CardContent>
						</Card>
					) : (
						devShells.map((shell) => (
							<Card key={shell.name}>
								<CardContent className="p-6">
									<div className="flex items-start justify-between">
										<div className="flex items-start gap-4">
											<div className="flex h-12 w-12 items-center  shrink-0 justify-center rounded-lg bg-accent/10">
												<Terminal className="h-6 w-6 text-accent" />
											</div>
											<div>
												<div className="flex items-center gap-2">
													<h3 className="font-medium text-foreground">
														{shell.name}
													</h3>
													{shell.active && (
														<Badge
															className="border-accent text-accent"
															variant="outline"
														>
															Active
														</Badge>
													)}
												</div>
												<p className="mt-1 text-muted-foreground text-sm">
													{shell.description}
												</p>

												<div className="mt-4 space-y-3">
													<div className="flex items-center gap-2">
														<Code className="h-4 w-4 text-muted-foreground" />
														<div className="flex flex-wrap gap-1">
															{shell.languages.map((lang) => (
																<Badge
																	className="text-xs"
																	key={lang}
																	variant="secondary"
																>
																	{lang}
																</Badge>
															))}
														</div>
													</div>
													<div className="flex items-center gap-2">
														<Package className="h-4 w-4 text-muted-foreground" />
														<div className="flex flex-wrap gap-1">
															{shell.tools
																.slice(0, visibleItems)
																.map((tool) => (
																	<Badge
																		className="text-xs"
																		key={tool}
																		variant="outline"
																	>
																		{tool}
																	</Badge>
																))}
															{shell.tools.length > visibleItems && (
																<Badge className="text-xs" variant="outline">
																	{shell.tools.length - visibleItems}+
																</Badge>
															)}
														</div>
													</div>
													{shell.hooks.length > 0 && (
														<div className="flex items-center gap-2">
															<GitBranch className="h-4 w-4 text-muted-foreground" />
															<div className="flex flex-wrap gap-1">
																{shell.hooks.map((hook) => (
																	<Badge
																		className="border-accent/50 text-accent text-xs"
																		key={hook}
																		variant="outline"
																	>
																		{hook}
																	</Badge>
																))}
															</div>
														</div>
													)}
												</div>
											</div>
										</div>

										<div className="flex items-center gap-4">
											<div className="flex items-center gap-2">
												<Label
													className="text-muted-foreground text-sm"
													htmlFor={`active-${shell.name}`}
												>
													Active
												</Label>
												<Switch
													checked={shell.active}
													id={`active-${shell.name}`}
												/>
											</div>
											<Button size="sm" variant="outline">
												Edit
											</Button>
										</div>
									</div>
								</CardContent>
							</Card>
						))
					)}
				</TabsContent>

				<TabsContent className="mt-6" value="tools">
					{availableTools.length === 0 ? (
						<Card>
							<CardContent className="p-6">
								<p className="text-muted-foreground text-sm">
									No installed tools detected yet.
								</p>
							</CardContent>
						</Card>
					) : (
						<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
							{availableTools.map((tool) => (
								<Card
									className="cursor-pointer transition-colors hover:border-accent/50"
									key={tool.id}
								>
									<CardContent className="flex items-center gap-4 p-4">
										<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
											<Package className="h-5 w-5 text-muted-foreground" />
										</div>
										<div className="flex-1">
											<p className="font-medium text-foreground">{tool.name}</p>
											<p className="text-muted-foreground text-sm">
												{tool.version}
											</p>
										</div>
										<Badge className="text-xs" variant="outline">
											{tool.category}
										</Badge>
									</CardContent>
								</Card>
							))}
						</div>
					)}
				</TabsContent>

				<TabsContent className="mt-6 space-y-4" value="scripts">
					<Card>
						<CardHeader>
							<CardTitle className="flex items-center gap-2 text-base">
								<FileCode className="h-5 w-5 text-accent" />
								Available Scripts
							</CardTitle>
						</CardHeader>
						<CardContent className="space-y-3">
							{scripts.length === 0 ? (
								<p className="text-muted-foreground text-sm">
									No scripts configured yet.
								</p>
							) : (
								scripts.map((script) => (
									<div
										className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
										key={script.name}
									>
										<div className="flex items-center gap-3">
											<code className="font-medium text-accent text-sm">
												{script.name}
											</code>
											<span className="text-muted-foreground text-sm">
												{script.description}
											</span>
										</div>
										<Button className="gap-2" size="sm" variant="ghost">
											<Play className="h-4 w-4" />
											Run
										</Button>
									</div>
								))
							)}
						</CardContent>
					</Card>
				</TabsContent>
			</Tabs>
		</div>
	);
}
