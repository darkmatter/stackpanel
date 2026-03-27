"use client";

import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@ui/dialog";
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
import {
	Cloud,
	Database,
	Globe,
	Loader2,
	Plus,
	Server,
	Sparkles,
	Terminal,
} from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { useNixConfig } from "@/lib/use-agent";
import {
	type Ec2AppConfig,
	DEFAULT_EC2_APP,
	DEFAULT_EC2_MACHINE_META,
	type useEc2Provisioning,
} from "./use-machines";

// =============================================================================
// Presets
// =============================================================================

interface Preset {
	id: string;
	label: string;
	description: string;
	icon: typeof Server;
	appId: string;
	instanceCount: number;
	instanceType: string;
	osType: "ubuntu" | "nixos";
	roles: string[];
	tags: string[];
	targetEnv: string;
	rootVolumeSize: number | null;
}

/**
 * Derive presets from the user's configured apps.
 *
 * For each app we look at type, framework, deployment settings, and container
 * config to suggest sane EC2 defaults.
 */
function derivePresets(
	nixConfig: Record<string, unknown> | null | undefined,
	existingAppIds: Set<string>,
): Preset[] {
	if (!nixConfig) return [];

	const rawApps = (nixConfig.apps ?? nixConfig.appsComputed ?? {}) as Record<
		string,
		Record<string, unknown>
	>;
	const presets: Preset[] = [];

	for (const [appName, app] of Object.entries(rawApps)) {
		const appType = (app.type as string) ?? "bun";
		const framework = app.framework as Record<string, Record<string, unknown>> | undefined;
		const deployment = app.deployment as Record<string, unknown> | undefined;
		const container = app.container as Record<string, unknown> | undefined;
		// Determine the kind of workload for sizing heuristics
		const isGo = appType === "go";
		const hasContainer = container?.enable === true;
		const deployHost = deployment?.host as string | undefined;

		// Detect framework
		const isTanStack = framework?.["tanstack-start"]?.enable === true || framework?.["tanstack_start"]?.enable === true;
		const isNextjs = framework?.nextjs?.enable === true;
		const isVite = framework?.vite?.enable === true;
		const isHono = framework?.hono?.enable === true;
		const isAstro = framework?.astro?.enable === true;
		const isStaticSite = isVite || isAstro;
		const isSSR = isTanStack || isNextjs;
		const isApi = isHono || isGo;

		// Skip apps already deployed to non-EC2 hosts (cloudflare, fly)
		// but still offer them if deployment is disabled or host is null/aws
		if (deployHost && deployHost !== "aws" && deployment?.enable === true) {
			continue;
		}

		// Build preset
		let icon = Server;
		let instanceType = "t3.micro";
		let instanceCount = 1;
		let roles: string[] = [appName];
		let rootVolumeSize: number | null = null;

		if (isSSR) {
			// SSR frameworks need more RAM for rendering
			icon = Globe;
			instanceType = "t3.small";
			instanceCount = 2;
			roles = [appName, "web"];
			rootVolumeSize = 20;
		} else if (isApi) {
			icon = Terminal;
			instanceType = isGo ? "t3.micro" : "t3.small";
			instanceCount = 2;
			roles = [appName, "api"];
		} else if (isStaticSite) {
			icon = Cloud;
			instanceType = "t3.micro";
			instanceCount = 1;
			roles = [appName, "web"];
		} else if (hasContainer) {
			icon = Database;
			instanceType = "t3.small";
			instanceCount = 1;
			roles = [appName];
			rootVolumeSize = 30;
		} else {
			// Generic app
			instanceType = "t3.micro";
			roles = [appName];
		}

		const frameworkLabel = isTanStack
			? "TanStack Start"
			: isNextjs
				? "Next.js"
				: isHono
					? "Hono"
					: isVite
						? "Vite"
						: isAstro
							? "Astro"
							: isGo
								? "Go"
								: appType;

		presets.push({
			id: appName,
			label: appName,
			description: `${frameworkLabel} · ${instanceCount}x ${instanceType}`,
			icon,
			appId: appName,
			instanceCount,
			instanceType,
			osType: "ubuntu",
			roles,
			tags: [],
			targetEnv: "production",
			rootVolumeSize,
		});
	}

	// Add generic presets if the user has few apps
	if (!existingAppIds.has("database")) {
		presets.push({
			id: "_preset_database",
			label: "Database Server",
			description: "PostgreSQL/Redis · 1x t3.medium · 50GB",
			icon: Database,
			appId: "database",
			instanceCount: 1,
			instanceType: "t3.medium",
			osType: "ubuntu",
			roles: ["database"],
			tags: [],
			targetEnv: "production",
			rootVolumeSize: 50,
		});
	}

	return presets;
}

// =============================================================================
// Dialog
// =============================================================================

interface ProvisionInstanceDialogProps {
	ec2: ReturnType<typeof useEc2Provisioning>;
}

const INSTANCE_TYPES = [
	"t3.micro",
	"t3.small",
	"t3.medium",
	"t3.large",
	"t3.xlarge",
	"t3.2xlarge",
	"m6i.large",
	"m6i.xlarge",
	"m6i.2xlarge",
	"c6i.large",
	"c6i.xlarge",
	"c6i.2xlarge",
	"r6i.large",
	"r6i.xlarge",
];

export function ProvisionInstanceDialog({ ec2 }: ProvisionInstanceDialogProps) {
	const { data: nixConfig } = useNixConfig();
	const [open, setOpen] = useState(false);
	const [saving, setSaving] = useState(false);

	// Form state
	const [appId, setAppId] = useState("");
	const [instanceCount, setInstanceCount] = useState(1);
	const [instanceType, setInstanceType] = useState("t3.micro");
	const [osType, setOsType] = useState<"ubuntu" | "nixos">("ubuntu");
	const [vpcId, setVpcId] = useState("");
	const [subnetIds, setSubnetIds] = useState("");
	const [rootVolumeSize, setRootVolumeSize] = useState("");
	const [associatePublicIp, setAssociatePublicIp] = useState(true);
	const [createSg, setCreateSg] = useState(true);
	const [createKeyPair, setCreateKeyPair] = useState(false);
	const [publicKey, setPublicKey] = useState("");
	const [enableIam, setEnableIam] = useState(true);
	const [roles, setRoles] = useState("");
	const [tags, setTags] = useState("");
	const [targetEnv, setTargetEnv] = useState("");

	const existingAppIds = useMemo(
		() => new Set(Object.keys(ec2.config.apps)),
		[ec2.config.apps],
	);

	const presets = useMemo(
		() => derivePresets(nixConfig as Record<string, unknown> | null, existingAppIds),
		[nixConfig, existingAppIds],
	);

	const applyPreset = (preset: Preset) => {
		setAppId(preset.appId);
		setInstanceCount(preset.instanceCount);
		setInstanceType(preset.instanceType);
		setOsType(preset.osType);
		setRoles(preset.roles.join(", "));
		setTags(preset.tags.join(", "));
		setTargetEnv(preset.targetEnv);
		setRootVolumeSize(preset.rootVolumeSize?.toString() ?? "");
		// Keep networking/SSH/IAM at their current (default) values
	};

	const resetForm = () => {
		setAppId("");
		setInstanceCount(1);
		setInstanceType("t3.micro");
		setOsType("ubuntu");
		setVpcId("");
		setSubnetIds("");
		setRootVolumeSize("");
		setAssociatePublicIp(true);
		setCreateSg(true);
		setCreateKeyPair(false);
		setPublicKey("");
		setEnableIam(true);
		setRoles("");
		setTags("");
		setTargetEnv("");
	};

	const handleOpenChange = (isOpen: boolean) => {
		setOpen(isOpen);
		if (!isOpen) resetForm();
	};

	const isValid = appId.trim().length > 0 && /^[a-z0-9-]+$/.test(appId.trim());

	const handleSubmit = async () => {
		const id = appId.trim();
		if (!id) {
			toast.error("App ID is required");
			return;
		}
		if (ec2.config.apps[id]) {
			toast.error(`EC2 app "${id}" already exists`);
			return;
		}

		setSaving(true);
		try {
			const appConfig: Ec2AppConfig = {
				...DEFAULT_EC2_APP,
				instance_count: instanceCount,
				instance_type: instanceType,
				os_type: osType,
				vpc_id: vpcId || null,
				subnet_ids: subnetIds
					? subnetIds.split(",").map((s) => s.trim()).filter(Boolean)
					: [],
				root_volume_size: rootVolumeSize ? Number.parseInt(rootVolumeSize, 10) : null,
				associate_public_ip: associatePublicIp,
				security_group: {
					...DEFAULT_EC2_APP.security_group,
					create: createSg,
				},
				key_pair: {
					create: createKeyPair,
					name: createKeyPair ? `${id}-key` : null,
					public_key: createKeyPair ? publicKey || null : null,
				},
				iam: {
					enable: enableIam,
					role_name: enableIam ? `${id}-ec2-role` : null,
				},
				tags: {
					Name: id,
					ManagedBy: "stackpanel-infra",
				},
				machine: {
					...DEFAULT_EC2_MACHINE_META,
					roles: roles ? roles.split(",").map((s) => s.trim()).filter(Boolean) : [],
					tags: tags ? tags.split(",").map((s) => s.trim()).filter(Boolean) : [],
					target_env: targetEnv || null,
				},
			};

			await ec2.addApp(id, appConfig);
			toast.success(`EC2 app "${id}" configured with ${instanceCount} instance(s). Run infra:deploy to provision.`);
			handleOpenChange(false);
		} catch (err) {
			toast.error(err instanceof Error ? err.message : "Failed to add EC2 app");
		} finally {
			setSaving(false);
		}
	};

	return (
		<Dialog open={open} onOpenChange={handleOpenChange}>
			<Button className="gap-2" size="sm" variant="outline" onClick={() => setOpen(true)}>
				<Plus className="h-4 w-4" />
				Provision EC2
			</Button>
			<DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Provision EC2 Instances</DialogTitle>
					<DialogDescription>
						Define EC2 instances to provision. Run <code className="text-xs bg-secondary px-1 py-0.5 rounded">infra:deploy</code> after to create them.
					</DialogDescription>
				</DialogHeader>

				<div className="space-y-4 py-4">
					{/* Presets */}
					{presets.length > 0 && (
						<div className="space-y-2">
							<div className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
								<Sparkles className="h-3 w-3" />
								Presets from your apps
							</div>
							<div className="flex flex-wrap gap-2">
								{presets.map((preset) => {
									const Icon = preset.icon;
									const isActive = appId === preset.appId;
									return (
										<button
											key={preset.id}
											type="button"
											onClick={() => applyPreset(preset)}
											className={`
												inline-flex items-center gap-2 rounded-lg border px-3 py-2
												text-left text-sm transition-colors cursor-pointer
												${isActive
													? "border-primary bg-primary/5 text-primary"
													: "border-border bg-card text-foreground hover:border-primary/40 hover:bg-secondary/50"
												}
											`}
										>
											<Icon className="h-4 w-4 shrink-0" />
											<div className="min-w-0">
												<div className="font-medium">{preset.label}</div>
												<div className="text-[10px] text-muted-foreground">{preset.description}</div>
											</div>
										</button>
									);
								})}
							</div>
						</div>
					)}

					{/* Identity */}
					<div className="space-y-2">
						<Label>App ID</Label>
						<Input
							placeholder="web-server"
							value={appId}
							onChange={(e) => setAppId(e.target.value)}
						/>
						<p className="text-xs text-muted-foreground">
							Unique identifier for this group of instances
						</p>
					</div>

					{/* Instance sizing */}
					<div className="grid grid-cols-3 gap-3">
						<div className="space-y-2">
							<Label>Count</Label>
							<Input
								type="number"
								min={1}
								max={20}
								value={instanceCount}
								onChange={(e) => setInstanceCount(Number.parseInt(e.target.value, 10) || 1)}
							/>
						</div>
						<div className="space-y-2">
							<Label>Instance Type</Label>
							<Select value={instanceType} onValueChange={setInstanceType}>
								<SelectTrigger>
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									{INSTANCE_TYPES.map((t) => (
										<SelectItem key={t} value={t}>{t}</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
						<div className="space-y-2">
							<Label>OS</Label>
							<Select value={osType} onValueChange={(v) => setOsType(v as "ubuntu" | "nixos")}>
								<SelectTrigger>
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									<SelectItem value="ubuntu">Ubuntu 24.04</SelectItem>
									<SelectItem value="nixos">NixOS</SelectItem>
								</SelectContent>
							</Select>
						</div>
					</div>

					{/* Networking */}
					<fieldset className="rounded-lg border border-border p-4 space-y-3">
						<legend className="px-2 text-sm font-medium">Networking</legend>

						<div className="grid grid-cols-2 gap-3">
							<div className="space-y-2">
								<Label>VPC ID</Label>
								<Input
									placeholder="Leave blank for default VPC"
									value={vpcId}
									onChange={(e) => setVpcId(e.target.value)}
								/>
							</div>
							<div className="space-y-2">
								<Label>Subnet IDs</Label>
								<Input
									placeholder="Leave blank for auto"
									value={subnetIds}
									onChange={(e) => setSubnetIds(e.target.value)}
								/>
							</div>
						</div>

						<div className="flex items-center justify-between">
							<div>
								<Label>Public IP</Label>
								<p className="text-xs text-muted-foreground">Associate a public IPv4 address</p>
							</div>
							<Switch checked={associatePublicIp} onCheckedChange={setAssociatePublicIp} />
						</div>

						<div className="flex items-center justify-between">
							<div>
								<Label>Security Group</Label>
								<p className="text-xs text-muted-foreground">Auto-create with SSH, HTTP, HTTPS ingress</p>
							</div>
							<Switch checked={createSg} onCheckedChange={setCreateSg} />
						</div>
					</fieldset>

					{/* Storage */}
					<div className="space-y-2">
						<Label>Root Volume Size (GB)</Label>
						<Input
							placeholder="Default (8 GB)"
							value={rootVolumeSize}
							onChange={(e) => setRootVolumeSize(e.target.value)}
						/>
					</div>

					{/* SSH Key */}
					<fieldset className="rounded-lg border border-border p-4 space-y-3">
						<legend className="px-2 text-sm font-medium">SSH Key Pair</legend>

						<div className="flex items-center justify-between">
							<div>
								<Label>Create Key Pair</Label>
								<p className="text-xs text-muted-foreground">Import your public key to AWS</p>
							</div>
							<Switch checked={createKeyPair} onCheckedChange={setCreateKeyPair} />
						</div>

						{createKeyPair && (
							<div className="space-y-2">
								<Label>Public Key</Label>
								<Input
									placeholder="ssh-ed25519 AAAA..."
									value={publicKey}
									onChange={(e) => setPublicKey(e.target.value)}
								/>
							</div>
						)}
					</fieldset>

					{/* IAM */}
					<div className="flex items-center justify-between">
						<div>
							<Label>IAM Instance Profile</Label>
							<p className="text-xs text-muted-foreground">Create role with SSM + ECR access</p>
						</div>
						<Switch checked={enableIam} onCheckedChange={setEnableIam} />
					</div>

					{/* Machine metadata */}
					<fieldset className="rounded-lg border border-border p-4 space-y-3">
						<legend className="px-2 text-sm font-medium">Machine Metadata</legend>

						<div className="grid grid-cols-2 gap-3">
							<div className="space-y-2">
								<Label>Roles</Label>
								<Input
									placeholder="web, app (comma-separated)"
									value={roles}
									onChange={(e) => setRoles(e.target.value)}
								/>
							</div>
							<div className="space-y-2">
								<Label>Tags</Label>
								<Input
									placeholder="production, us-west"
									value={tags}
									onChange={(e) => setTags(e.target.value)}
								/>
							</div>
						</div>

						<div className="space-y-2">
							<Label>Environment</Label>
							<Select value={targetEnv} onValueChange={setTargetEnv}>
								<SelectTrigger>
									<SelectValue placeholder="Select..." />
								</SelectTrigger>
								<SelectContent>
									<SelectItem value="production">Production</SelectItem>
									<SelectItem value="staging">Staging</SelectItem>
									<SelectItem value="development">Development</SelectItem>
								</SelectContent>
							</Select>
						</div>
					</fieldset>
				</div>

				<DialogFooter>
					<Button variant="outline" onClick={() => handleOpenChange(false)}>Cancel</Button>
					<Button onClick={handleSubmit} disabled={!isValid || saving}>
						{saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
						Add to Config
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
