"use client";

/**
 * Deploy Panel - Colmena-centric deployment management.
 *
 * Shows machine inventory, app-to-machine mapping, and deploy actions
 * (eval/build/apply). Supports full machine CRUD (add/edit/delete) and
 * AWS EC2 discovery configuration.
 */

import { useState, useMemo } from "react";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import {
	Activity,
	AlertCircle,
	CheckCircle,
	CloudOff,
	Cpu,
	HardDrive,
	Loader2,
	Network,
	Pencil,
	Play,
	RefreshCw,
	Rocket,
	Server,
	Settings,
	Shield,
	XCircle,
} from "lucide-react";
import { toast } from "sonner";
import { useAgentContext } from "@/lib/agent-provider";
import { useNixConfig } from "@/lib/use-agent";
import { PanelHeader } from "../shared/panel-header";
import { cn } from "@/lib/utils";
import { AddMachineDialog } from "./add-machine-dialog";
import { EditMachineDialog } from "./edit-machine-dialog";
import { useMachinesConfig, type MachineConfig } from "./use-machines";

// =============================================================================
// Types
// =============================================================================

interface MachineInfo {
	id: string;
	name: string;
	host: string | null;
	ssh: {
		user: string;
		port: number;
		keyPath: string | null;
	};
	tags: string[];
	roles: string[];
	provider: string | null;
	arch: string | null;
	publicIp: string | null;
	privateIp: string | null;
	targetEnv: string | null;
	labels: Record<string, string>;
}

interface AppDeployMapping {
	enable: boolean;
	targets: string[];
	resolvedTargets: string[];
	role: string | null;
	nixosModules: string[];
	system: string | null;
}

interface ColmenaConfig {
	enable: boolean;
	machineSource: string;
	generateHive: boolean;
	config: string;
	machineCount: number;
	machineIds: string[];
}

// =============================================================================
// Hooks
// =============================================================================

function useColmenaData() {
	const { data: nixConfig, isLoading, refetch } = useNixConfig();

	const result = useMemo(() => {
		const cfg = nixConfig as Record<string, unknown> | null | undefined;
		if (!cfg) return { machines: {}, appDeploy: {}, colmenaConfig: null };

		const serializable = cfg.serializable as Record<string, unknown> | undefined;
		const colmenaConfig = (serializable?.colmena ?? null) as ColmenaConfig | null;

		const colmenaData = cfg.colmena as Record<string, unknown> | undefined;
		const machinesComputed = (colmenaData?.machinesComputed ?? {}) as Record<string, MachineInfo>;

		const rawApps = (cfg.apps ?? cfg.appsComputed ?? {}) as Record<string, Record<string, unknown>>;
		const appDeploy: Record<string, AppDeployMapping> = {};

		for (const [appName, appCfg] of Object.entries(rawApps)) {
			const deploy = appCfg.deploy as Record<string, unknown> | undefined;
			if (deploy?.enable) {
				appDeploy[appName] = {
					enable: true,
					targets: (deploy.targets as string[]) ?? [],
					resolvedTargets: (deploy.resolvedTargets as string[]) ?? [],
					role: (deploy.role as string | null) ?? null,
					nixosModules: (deploy.nixosModules as string[]) ?? [],
					system: (deploy.system as string | null) ?? null,
				};
			}
		}

		return { machines: machinesComputed, appDeploy, colmenaConfig };
	}, [nixConfig]);

	return { ...result, isLoading, refetch };
}

// =============================================================================
// Sub-components
// =============================================================================

function MachineCard({
	machine,
	onEdit,
}: {
	machine: MachineInfo;
	onEdit?: () => void;
}) {
	const isReachable = machine.host !== null;

	return (
		<Card
			className={cn(
				"transition-colors cursor-pointer hover:border-primary/40",
				isReachable ? "border-border" : "border-amber-500/30",
			)}
			onClick={onEdit}
		>
			<CardContent className="p-4">
				<div className="flex items-start justify-between mb-3">
					<div className="flex items-center gap-2">
						<Server className="h-4 w-4 text-muted-foreground" />
						<span className="font-medium text-sm">{machine.name || machine.id}</span>
					</div>
					<div className="flex items-center gap-1.5">
						{onEdit && (
							<Button variant="ghost" size="icon" className="h-6 w-6" onClick={(e) => { e.stopPropagation(); onEdit(); }}>
								<Pencil className="h-3 w-3" />
							</Button>
						)}
						{isReachable ? (
							<Badge variant="secondary" className="text-[10px] gap-1">
								<CheckCircle className="h-3 w-3 text-green-500" />
								{machine.host}
							</Badge>
						) : (
							<Badge variant="outline" className="text-[10px] gap-1 text-amber-500 border-amber-500/30">
								<XCircle className="h-3 w-3" />
								no host
							</Badge>
						)}
					</div>
				</div>

				<div className="grid grid-cols-2 gap-2 text-xs text-muted-foreground">
					<div className="flex items-center gap-1.5">
						<Shield className="h-3 w-3" />
						<span>{machine.ssh.user}@{machine.ssh.port}</span>
					</div>
					{machine.arch && (
						<div className="flex items-center gap-1.5">
							<Cpu className="h-3 w-3" />
							<span>{machine.arch}</span>
						</div>
					)}
					{machine.provider && (
						<div className="flex items-center gap-1.5">
							<HardDrive className="h-3 w-3" />
							<span>{machine.provider}</span>
						</div>
					)}
					{machine.targetEnv && (
						<div className="flex items-center gap-1.5">
							<Activity className="h-3 w-3" />
							<span>{machine.targetEnv}</span>
						</div>
					)}
				</div>

				{(machine.tags.length > 0 || machine.roles.length > 0) && (
					<div className="mt-2 flex flex-wrap gap-1">
						{machine.roles.map((role) => (
							<Badge key={`role-${role}`} variant="default" className="text-[10px] px-1.5 py-0">
								{role}
							</Badge>
						))}
						{machine.tags.map((tag) => (
							<Badge key={`tag-${tag}`} variant="secondary" className="text-[10px] px-1.5 py-0">
								{tag}
							</Badge>
						))}
					</div>
				)}
			</CardContent>
		</Card>
	);
}

function AppTargetRow({
	appName,
	deploy,
	machines,
}: {
	appName: string;
	deploy: AppDeployMapping;
	machines: Record<string, MachineInfo>;
}) {
	const resolvedNames = deploy.resolvedTargets.map(
		(id) => machines[id]?.name ?? id,
	);

	return (
		<div className="flex items-center justify-between rounded-lg border border-border bg-card p-3">
			<div className="flex items-center gap-3">
				<div className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/10">
					<Rocket className="h-4 w-4 text-primary" />
				</div>
				<div>
					<p className="font-medium text-sm">{appName}</p>
					<p className="text-xs text-muted-foreground">
						{deploy.targets.length > 0
							? `Targets: ${deploy.targets.join(", ")}`
							: deploy.role
								? `Role: ${deploy.role}`
								: "No targets defined"}
					</p>
				</div>
			</div>
			<div className="flex items-center gap-2">
				{deploy.role && (
					<Badge variant="outline" className="text-[10px]">
						{deploy.role}
					</Badge>
				)}
				<Badge variant="secondary" className="text-[10px]">
					{resolvedNames.length} machine{resolvedNames.length !== 1 ? "s" : ""}
				</Badge>
			</div>
		</div>
	);
}

// =============================================================================
// Settings: AWS EC2 Discovery Configuration
// =============================================================================

function AwsEc2Settings({ machines }: { machines: ReturnType<typeof useMachinesConfig> }) {
	const cfg = machines.config.aws;
	const [saving, setSaving] = useState(false);
	const [region, setRegion] = useState(cfg.region ?? "");
	const [sshUser, setSshUser] = useState(cfg.ssh.user);
	const [sshPort, setSshPort] = useState(cfg.ssh.port);
	const [sshKeyPath, setSshKeyPath] = useState(cfg.ssh.key_path ?? "");
	const [hostPref, setHostPref] = useState(cfg.host_preference.join(", "));

	const handleSave = async () => {
		setSaving(true);
		try {
			await machines.updateSettings({
				source: "aws-ec2",
				enable: true,
				aws: {
					...cfg,
					region: region || null,
					ssh: {
						user: sshUser || "root",
						port: sshPort || 22,
						key_path: sshKeyPath || null,
					},
					host_preference: hostPref.split(",").map((s) => s.trim()).filter(Boolean),
				},
			});
			toast.success("AWS EC2 settings saved");
		} catch (err) {
			toast.error(err instanceof Error ? err.message : "Failed to save");
		} finally {
			setSaving(false);
		}
	};

	return (
		<Card>
			<CardHeader>
				<CardTitle className="text-base">AWS EC2 Discovery</CardTitle>
				<CardDescription>
					Auto-discover machines from running EC2 instances
				</CardDescription>
			</CardHeader>
			<CardContent className="space-y-4">
				<div className="grid grid-cols-2 gap-3">
					<div className="space-y-2">
						<Label>Region</Label>
						<Input
							placeholder="us-west-2"
							value={region}
							onChange={(e) => setRegion(e.target.value)}
						/>
					</div>
					<div className="space-y-2">
						<Label>Host Preference</Label>
						<Input
							placeholder="publicDns, publicIp, privateIp"
							value={hostPref}
							onChange={(e) => setHostPref(e.target.value)}
						/>
					</div>
				</div>

				<fieldset className="rounded-lg border border-border p-3 space-y-3">
					<legend className="px-2 text-sm font-medium">Default SSH</legend>
					<div className="grid grid-cols-3 gap-3">
						<div className="space-y-2">
							<Label>User</Label>
							<Input
								placeholder="ec2-user"
								value={sshUser}
								onChange={(e) => setSshUser(e.target.value)}
							/>
						</div>
						<div className="space-y-2">
							<Label>Port</Label>
							<Input
								type="number"
								value={sshPort}
								onChange={(e) => setSshPort(Number.parseInt(e.target.value, 10) || 22)}
							/>
						</div>
						<div className="space-y-2">
							<Label>Key Path</Label>
							<Input
								placeholder="~/.ssh/aws"
								value={sshKeyPath}
								onChange={(e) => setSshKeyPath(e.target.value)}
							/>
						</div>
					</div>
				</fieldset>

				<Button onClick={handleSave} disabled={saving} size="sm">
					{saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
					Save Settings
				</Button>
			</CardContent>
		</Card>
	);
}

// =============================================================================
// Main Component
// =============================================================================

export function DeployPanel() {
	const { isConnected } = useAgentContext();
	const { machines: computedMachines, appDeploy, colmenaConfig, isLoading, refetch } = useColmenaData();
	const machinesConfig = useMachinesConfig();
	const [isRefreshing, setIsRefreshing] = useState(false);
	const [editingMachine, setEditingMachine] = useState<{ id: string; config: MachineConfig } | null>(null);

	// Merge computed machines (from colmena/infra) with static config machines
	const configMachines = machinesConfig.config.machines;
	const computedList = Object.values(computedMachines);
	const configList = Object.entries(configMachines);

	// Build combined machine list: computed takes precedence, config fills gaps
	const allMachineEntries = useMemo(() => {
		const seen = new Set<string>();
		const entries: Array<{ id: string; info: MachineInfo; configurable: boolean }> = [];

		// Add computed machines
		for (const m of computedList) {
			seen.add(m.id);
			entries.push({ id: m.id, info: m, configurable: !!configMachines[m.id] });
		}

		// Add config-only machines not in computed
		for (const [key, cfg] of configList) {
			if (!seen.has(key)) {
				entries.push({
					id: key,
					info: {
						id: key,
						name: cfg.name ?? key,
						host: cfg.host,
						ssh: { user: cfg.ssh.user, port: cfg.ssh.port, keyPath: cfg.ssh.key_path },
						tags: cfg.tags,
						roles: cfg.roles,
						provider: cfg.provider,
						arch: cfg.arch,
						publicIp: cfg.public_ip,
						privateIp: cfg.private_ip,
						targetEnv: cfg.target_env,
						labels: cfg.labels,
					},
					configurable: true,
				});
			}
		}

		return entries;
	}, [computedList, configList, configMachines]);

	const machineCount = allMachineEntries.length;
	const appDeployEntries = Object.entries(appDeploy);
	const healthyCount = allMachineEntries.filter((m) => m.info.host !== null).length;
	const unhealthyCount = machineCount - healthyCount;

	const handleRefresh = async () => {
		setIsRefreshing(true);
		try {
			await Promise.all([refetch(), machinesConfig.refetch()]);
		} finally {
			setIsRefreshing(false);
		}
	};

	if (!isConnected) {
		return (
			<div className="space-y-6">
				<PanelHeader
					title="Deploy"
					description="Machine inventory and deployment management"
				/>
				<Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
					<CardContent className="flex flex-col items-center justify-center gap-4 p-8">
						<CloudOff className="h-12 w-12 text-muted-foreground" />
						<div className="text-center">
							<p className="font-medium text-foreground">Agent Not Connected</p>
							<p className="text-muted-foreground text-sm">
								Connect to the stackpanel agent to manage deployments.
							</p>
						</div>
					</CardContent>
				</Card>
			</div>
		);
	}

	if (isLoading) {
		return (
			<div className="flex min-h-[400px] items-center justify-center">
				<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
			</div>
		);
	}

	return (
		<div className="space-y-6">
			<PanelHeader
				title="Deploy"
				description="Machine inventory and deployment management"
				actions={
					<div className="flex items-center gap-2">
						<AddMachineDialog machines={machinesConfig} />
						<Button
							variant="outline"
							size="sm"
							onClick={handleRefresh}
							disabled={isRefreshing}
						>
							<RefreshCw
								className={cn("mr-2 h-4 w-4", isRefreshing && "animate-spin")}
							/>
							{isRefreshing ? "Refreshing..." : "Refresh"}
						</Button>
					</div>
				}
			/>

			{/* Status overview */}
			<div className="grid gap-4 sm:grid-cols-4">
				<Card>
					<CardContent className="flex items-center gap-3 p-4">
						<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
							<Server className="h-5 w-5 text-primary" />
						</div>
						<div>
							<p className="text-muted-foreground text-xs">Machines</p>
							<p className="font-medium text-foreground">{machineCount}</p>
						</div>
					</CardContent>
				</Card>
				<Card>
					<CardContent className="flex items-center gap-3 p-4">
						<div className={cn(
							"flex h-10 w-10 items-center justify-center rounded-lg",
							healthyCount > 0 ? "bg-green-500/10" : "bg-secondary",
						)}>
							<CheckCircle className={cn(
								"h-5 w-5",
								healthyCount > 0 ? "text-green-500" : "text-muted-foreground",
							)} />
						</div>
						<div>
							<p className="text-muted-foreground text-xs">Reachable</p>
							<p className="font-medium text-foreground">{healthyCount}</p>
						</div>
					</CardContent>
				</Card>
				<Card>
					<CardContent className="flex items-center gap-3 p-4">
						<div className={cn(
							"flex h-10 w-10 items-center justify-center rounded-lg",
							unhealthyCount > 0 ? "bg-amber-500/10" : "bg-secondary",
						)}>
							<AlertCircle className={cn(
								"h-5 w-5",
								unhealthyCount > 0 ? "text-amber-500" : "text-muted-foreground",
							)} />
						</div>
						<div>
							<p className="text-muted-foreground text-xs">Unreachable</p>
							<p className="font-medium text-foreground">{unhealthyCount}</p>
						</div>
					</CardContent>
				</Card>
				<Card>
					<CardContent className="flex items-center gap-3 p-4">
						<div className={cn(
							"flex h-10 w-10 items-center justify-center rounded-lg",
							appDeployEntries.length > 0 ? "bg-blue-500/10" : "bg-secondary",
						)}>
							<Rocket className={cn(
								"h-5 w-5",
								appDeployEntries.length > 0 ? "text-blue-500" : "text-muted-foreground",
							)} />
						</div>
						<div>
							<p className="text-muted-foreground text-xs">Deploy-enabled apps</p>
							<p className="font-medium text-foreground">{appDeployEntries.length}</p>
						</div>
					</CardContent>
				</Card>
			</div>

			<Tabs defaultValue="machines">
				<TabsList>
					<TabsTrigger value="machines">
						Machines
						{machineCount > 0 && (
							<Badge variant="secondary" className="ml-1.5 text-[10px] px-1.5 py-0">
								{machineCount}
							</Badge>
						)}
					</TabsTrigger>
					<TabsTrigger value="targets">
						App Targets
						{appDeployEntries.length > 0 && (
							<Badge variant="secondary" className="ml-1.5 text-[10px] px-1.5 py-0">
								{appDeployEntries.length}
							</Badge>
						)}
					</TabsTrigger>
					<TabsTrigger value="actions">Actions</TabsTrigger>
					<TabsTrigger value="settings">Settings</TabsTrigger>
				</TabsList>

				{/* Machines Tab */}
				<TabsContent className="mt-6 space-y-4" value="machines">
					{machineCount === 0 ? (
						<Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
							<CardContent className="flex flex-col items-center justify-center gap-4 p-8">
								<Server className="h-12 w-12 text-muted-foreground/50" />
								<div className="text-center">
									<p className="font-medium text-foreground">No Machines</p>
									<p className="text-muted-foreground text-sm max-w-md">
										Add machines manually using the <strong>Add Machine</strong> button above,
										or configure AWS EC2 discovery in Settings and run{" "}
										<code className="text-xs bg-secondary px-1 py-0.5 rounded">infra:deploy</code>.
									</p>
								</div>
							</CardContent>
						</Card>
					) : (
						<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
							{allMachineEntries.map((entry) => (
								<MachineCard
									key={entry.id}
									machine={entry.info}
									onEdit={
										entry.configurable
											? () => {
													const cfg = configMachines[entry.id];
													if (cfg) setEditingMachine({ id: entry.id, config: cfg });
												}
											: undefined
									}
								/>
							))}
						</div>
					)}
				</TabsContent>

				{/* App Targets Tab */}
				<TabsContent className="mt-6 space-y-4" value="targets">
					{appDeployEntries.length === 0 ? (
						<Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
							<CardContent className="flex flex-col items-center justify-center gap-4 p-8">
								<Network className="h-12 w-12 text-muted-foreground/50" />
								<div className="text-center">
									<p className="font-medium text-foreground">No App Targets</p>
									<p className="text-muted-foreground text-sm max-w-md">
										No apps have deployment enabled. Add <code className="text-xs bg-secondary px-1 py-0.5 rounded">deploy.enable = true</code> and <code className="text-xs bg-secondary px-1 py-0.5 rounded">deploy.targets</code> to your app config.
									</p>
								</div>
							</CardContent>
						</Card>
					) : (
						<div className="space-y-3">
							{appDeployEntries.map(([appName, deploy]) => (
								<AppTargetRow
									key={appName}
									appName={appName}
									deploy={deploy}
									machines={computedMachines}
								/>
							))}
						</div>
					)}
				</TabsContent>

				{/* Actions Tab */}
				<TabsContent className="mt-6 space-y-4" value="actions">
					<Card>
						<CardHeader>
							<CardTitle className="text-base">Colmena Actions</CardTitle>
							<CardDescription>
								Run Colmena commands against your fleet
							</CardDescription>
						</CardHeader>
						<CardContent className="space-y-4">
							{machineCount === 0 ? (
								<div className="rounded-lg border border-amber-500/50 bg-amber-500/10 p-4">
									<div className="flex items-center gap-3">
										<AlertCircle className="h-5 w-5 text-amber-500" />
										<p className="text-amber-700 dark:text-amber-300 text-sm">
											No machines in inventory. Add machines or configure EC2 discovery first.
										</p>
									</div>
								</div>
							) : (
								<>
									<div className="flex flex-wrap gap-3">
										<Button variant="outline" className="gap-2">
											<Settings className="h-4 w-4" />
											colmena eval
										</Button>
										<Button variant="outline" className="gap-2">
											<HardDrive className="h-4 w-4" />
											colmena build
										</Button>
										<Button className="gap-2">
											<Play className="h-4 w-4" />
											colmena apply
										</Button>
									</div>
									<p className="text-xs text-muted-foreground">
										Actions run the generated wrapper scripts with your configured defaults.
										Use the CLI for advanced options: <code className="bg-secondary px-1 py-0.5 rounded">colmena-apply --on tag:prod</code>
									</p>
								</>
							)}
						</CardContent>
					</Card>
				</TabsContent>

				{/* Settings Tab */}
				<TabsContent className="mt-6 space-y-4" value="settings">
					{/* Module enable + source selection */}
					<Card>
						<CardHeader>
							<CardTitle className="text-base">Machines Module</CardTitle>
							<CardDescription>
								Configure how machines are sourced for deployment
							</CardDescription>
						</CardHeader>
						<CardContent className="space-y-4">
							<div className="flex items-center justify-between">
								<div>
									<Label>Enable</Label>
									<p className="text-xs text-muted-foreground">
										Enable the machines infra module
									</p>
								</div>
								<Switch
									checked={machinesConfig.config.enable}
									onCheckedChange={(checked) =>
										machinesConfig.updateSettings({ enable: checked })
									}
								/>
							</div>

							<div className="space-y-2">
								<Label>Machine Source</Label>
								<Select
									value={machinesConfig.config.source}
									onValueChange={(v) =>
										machinesConfig.updateSettings({
											source: v as "static" | "aws-ec2",
										})
									}
								>
									<SelectTrigger>
										<SelectValue />
									</SelectTrigger>
									<SelectContent>
										<SelectItem value="static">Static (defined in config)</SelectItem>
										<SelectItem value="aws-ec2">AWS EC2 (auto-discover)</SelectItem>
									</SelectContent>
								</Select>
							</div>

							{colmenaConfig && (
								<div className="grid gap-3 sm:grid-cols-2 mt-4">
									<div className="rounded-lg border border-border bg-secondary/30 p-3">
										<p className="text-muted-foreground text-xs">Hive Config</p>
										<p className="font-medium text-foreground text-sm font-mono text-[11px]">
											{colmenaConfig.config ?? ".stackpanel/state/colmena/hive.nix"}
										</p>
									</div>
									<div className="rounded-lg border border-border bg-secondary/30 p-3">
										<p className="text-muted-foreground text-xs">Generate Hive</p>
										<p className="font-medium text-foreground text-sm">
											{colmenaConfig.generateHive ? "Yes" : "No"}
										</p>
									</div>
								</div>
							)}
						</CardContent>
					</Card>

					{/* AWS EC2 settings (shown when source is aws-ec2) */}
					{machinesConfig.config.source === "aws-ec2" && (
						<AwsEc2Settings machines={machinesConfig} />
					)}
				</TabsContent>
			</Tabs>

			{/* Edit dialog */}
			{editingMachine && (
				<EditMachineDialog
					machineId={editingMachine.id}
					machine={editingMachine.config}
					machines={machinesConfig}
					open={!!editingMachine}
					onOpenChange={(open) => {
						if (!open) setEditingMachine(null);
					}}
				/>
			)}
		</div>
	);
}
