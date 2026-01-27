"use client";

import { useState, useCallback } from "react";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@ui/card";
import { Field, FieldGroup, FieldRow, SwitchField } from "@ui/field";
import { Input } from "@ui/input";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { TooltipProvider } from "@ui/tooltip";
import {
	AlertCircle,
	Cloud,
	CloudOff,
	Loader2,
	Play,
	RefreshCw,
	Rocket,
	Save,
	Settings,
	Trash2,
} from "lucide-react";
import { useAgentContext } from "@/lib/agent-provider";
import { useVariablesBackend } from "@/lib/use-agent";
import { PanelHeader } from "../shared/panel-header";

// Types
interface DeploymentConfig {
	enable: boolean;
	provider: "fly";
	fly: {
		appName: string;
		region: string;
		memory: string;
		cpuKind: "shared" | "performance";
		cpus: number;
		autoStop: "off" | "stop" | "suspend";
		autoStart: boolean;
		minMachines: number;
		forceHttps: boolean;
		env: Record<string, string>;
	};
	container: {
		type: "bun" | "node" | "go" | "static" | "custom";
		port: number;
		buildCommand: string | null;
		entrypoint: string | null;
		aws: {
			enable: boolean;
			chamberService: string | null;
		};
	};
}

interface DeployableApp {
	name: string;
	path: string;
	config: DeploymentConfig;
	status: {
		deployed: boolean;
		lastDeployedAt?: string;
		url?: string;
	};
}

// Constants
const FLY_REGIONS = [
	{ value: "iad", label: "Ashburn, Virginia (US)" },
	{ value: "ord", label: "Chicago, Illinois (US)" },
	{ value: "sjc", label: "San Jose, California (US)" },
	{ value: "lax", label: "Los Angeles, California (US)" },
	{ value: "sea", label: "Seattle, Washington (US)" },
	{ value: "dfw", label: "Dallas, Texas (US)" },
	{ value: "ewr", label: "Secaucus, NJ (US)" },
	{ value: "yyz", label: "Toronto, Canada" },
	{ value: "lhr", label: "London, UK" },
	{ value: "ams", label: "Amsterdam, Netherlands" },
	{ value: "fra", label: "Frankfurt, Germany" },
	{ value: "cdg", label: "Paris, France" },
	{ value: "nrt", label: "Tokyo, Japan" },
	{ value: "sin", label: "Singapore" },
	{ value: "syd", label: "Sydney, Australia" },
];

const MEMORY_OPTIONS = ["256mb", "512mb", "1gb", "2gb", "4gb", "8gb"];

const CONTAINER_TYPES = [
	{ value: "bun", label: "Bun/TypeScript" },
	{ value: "node", label: "Node.js" },
	{ value: "go", label: "Go" },
	{ value: "static", label: "Static Site" },
	{ value: "custom", label: "Custom" },
];

// Default deployment config
const defaultConfig: DeploymentConfig = {
	enable: false,
	provider: "fly",
	fly: {
		appName: "",
		region: "iad",
		memory: "512mb",
		cpuKind: "shared",
		cpus: 1,
		autoStop: "suspend",
		autoStart: true,
		minMachines: 0,
		forceHttps: true,
		env: {},
	},
	container: {
		type: "bun",
		port: 3000,
		buildCommand: null,
		entrypoint: null,
		aws: {
			enable: false,
			chamberService: null,
		},
	},
};

// Status Card Component
function StatusCard({
	icon: Icon,
	label,
	value,
	active,
}: {
	icon: React.ElementType;
	label: string;
	value: string;
	active: boolean;
}) {
	return (
		<Card
			className={active ? "border-accent/50 bg-accent/5" : "border-border/50"}
		>
			<CardContent className="flex items-center gap-3 p-4">
				<div
					className={`flex h-10 w-10 items-center justify-center rounded-lg ${active ? "bg-accent/20" : "bg-secondary"}`}
				>
					<Icon
						className={`h-5 w-5 ${active ? "text-accent" : "text-muted-foreground"}`}
					/>
				</div>
				<div>
					<p className="text-muted-foreground text-xs">{label}</p>
					<p className="font-medium text-foreground">{value}</p>
				</div>
			</CardContent>
		</Card>
	);
}

export function DeployPanel() {
	const { isConnected } = useAgentContext();
	const { data: backendData } = useVariablesBackend();
	const isChamber = backendData?.backend === "chamber";
	const chamberServicePrefix = backendData?.chamber?.servicePrefix;

	// Mock data - in real implementation, this would come from the agent
	const [apps] = useState<DeployableApp[]>([
		{
			name: "web",
			path: "apps/web",
			config: {
				...defaultConfig,
				enable: true,
				fly: { ...defaultConfig.fly, appName: "stackpanel-web" },
			},
			status: { deployed: false },
		},
		{
			name: "server",
			path: "apps/server",
			config: defaultConfig,
			status: { deployed: false },
		},
	]);

	const [selectedApp, setSelectedApp] = useState<string>(apps[0]?.name || "");
	const [formData, setFormData] = useState<DeploymentConfig>(
		apps[0]?.config || defaultConfig,
	);
	const [hasChanges, setHasChanges] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	const [isDeploying, setIsDeploying] = useState(false);
	const [deployStage, setDeployStage] = useState("prod");
	const [deployOutput, setDeployOutput] = useState("");

	const currentApp = apps.find((a) => a.name === selectedApp);

	// Update form when app changes
	const handleAppChange = useCallback(
		(appName: string) => {
			setSelectedApp(appName);
			const app = apps.find((a) => a.name === appName);
			if (app) {
				setFormData(app.config);
				setHasChanges(false);
			}
		},
		[apps],
	);

	// Update form field
	const updateField = useCallback(
		<K extends keyof DeploymentConfig>(key: K, value: DeploymentConfig[K]) => {
			setFormData((prev) => ({ ...prev, [key]: value }));
			setHasChanges(true);
		},
		[],
	);

	// Update nested fly field
	const updateFlyField = useCallback(
		(key: keyof DeploymentConfig["fly"], value: unknown) => {
			setFormData((prev) => ({
				...prev,
				fly: { ...prev.fly, [key]: value },
			}));
			setHasChanges(true);
		},
		[],
	);

	// Update nested container field
	const updateContainerField = useCallback(
		(key: keyof DeploymentConfig["container"], value: unknown) => {
			setFormData((prev) => ({
				...prev,
				container: { ...prev.container, [key]: value },
			}));
			setHasChanges(true);
		},
		[],
	);

	// Update AWS config
	const updateAwsField = useCallback(
		(key: keyof DeploymentConfig["container"]["aws"], value: unknown) => {
			setFormData((prev) => ({
				...prev,
				container: {
					...prev.container,
					aws: { ...prev.container.aws, [key]: value },
				},
			}));
			setHasChanges(true);
		},
		[],
	);

	// Save configuration
	const handleSave = async () => {
		setIsSaving(true);
		// TODO: Call agent to save configuration
		await new Promise((resolve) => setTimeout(resolve, 1000));
		setIsSaving(false);
		setHasChanges(false);
	};

	// Run deploy step
	const handleDeployStep = async (step: "clean" | "build" | "push" | "full") => {
		setIsDeploying(true);
		setDeployOutput(`Running deploy:${selectedApp}:${step}...\n`);

		// Simulate deployment progress
		const steps =
			step === "full" ? ["clean", "build", "push", "deploy"] : [step];

		for (const s of steps) {
			setDeployOutput((prev) => prev + `\n$ turbo run deploy:${selectedApp}:${s}\n`);
			await new Promise((resolve) => setTimeout(resolve, 1500));
			setDeployOutput((prev) => prev + `Step ${s} complete.\n`);
		}

		setDeployOutput((prev) => prev + `\nDeployment complete!\n`);
		setIsDeploying(false);
	};

	// Not connected state
	if (!isConnected) {
		return (
			<TooltipProvider>
				<div className="space-y-6">
				<PanelHeader
					title="Deploy"
					description="Deploy applications to cloud providers"
				/>
					<Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
						<CardContent className="flex flex-col items-center justify-center gap-4 p-8">
							<CloudOff className="h-12 w-12 text-muted-foreground" />
							<div className="text-center">
								<p className="font-medium text-foreground">
									Agent Not Connected
								</p>
								<p className="text-muted-foreground text-sm">
									Connect to the stackpanel agent to manage deployments.
								</p>
							</div>
						</CardContent>
					</Card>
				</div>
			</TooltipProvider>
		);
	}

	const isEnabled = formData.enable;
	const isDeployed = currentApp?.status.deployed ?? false;

	return (
		<TooltipProvider>
			<div className="space-y-6">
			<PanelHeader
				title="Deploy"
				description="Deploy applications to cloud providers"
				actions={
						hasChanges && (
							<Button onClick={handleSave} disabled={isSaving} className="gap-2">
								{isSaving ? (
									<Loader2 className="h-4 w-4 animate-spin" />
								) : (
									<Save className="h-4 w-4" />
								)}
								Save Changes
							</Button>
						)
					}
				/>

				{/* App Selector */}
				<Card>
					<CardContent className="p-4">
						<FieldRow>
							<Field label="Select App">
								<Select value={selectedApp} onValueChange={handleAppChange}>
									<SelectTrigger>
										<SelectValue placeholder="Select an app" />
									</SelectTrigger>
									<SelectContent>
										{apps.map((app) => (
											<SelectItem key={app.name} value={app.name}>
												{app.name}{" "}
												{app.config.enable && (
													<Badge variant="secondary" className="ml-2">
														Configured
													</Badge>
												)}
											</SelectItem>
										))}
									</SelectContent>
								</Select>
							</Field>
						</FieldRow>
					</CardContent>
				</Card>

				{/* Status Cards */}
				<div className="grid gap-4 sm:grid-cols-3">
					<StatusCard
						icon={Settings}
						label="Enabled"
						value={isEnabled ? "Yes" : "No"}
						active={isEnabled}
					/>
					<StatusCard
						icon={Cloud}
						label="Deployed"
						value={isDeployed ? "Yes" : "No"}
						active={isDeployed}
					/>
					<StatusCard
						icon={Rocket}
						label="Provider"
						value={isEnabled ? "Fly.io" : "Not configured"}
						active={isEnabled}
					/>
				</div>

				{/* Tabs */}
				<Tabs defaultValue="status">
					<TabsList>
						<TabsTrigger value="status">Status</TabsTrigger>
						<TabsTrigger value="configure">Configure</TabsTrigger>
						<TabsTrigger value="deploy">Deploy</TabsTrigger>
						<TabsTrigger value="logs">Logs</TabsTrigger>
					</TabsList>

					{/* Status Tab */}
					<TabsContent className="mt-6 space-y-4" value="status">
						{!isEnabled ? (
							<Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
								<CardContent className="p-6">
									<p className="font-medium text-foreground text-sm">
										Deployment not configured
									</p>
									<p className="text-muted-foreground text-xs mt-1">
										Enable deployment in the Configure tab to deploy this app.
									</p>
								</CardContent>
							</Card>
						) : (
							<Card className="border-accent/20 bg-accent/5">
								<CardContent className="flex items-center gap-4 p-4">
									<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/20">
										<Rocket className="h-5 w-5 text-accent" />
									</div>
									<div className="flex-1">
										<p className="font-medium text-foreground text-sm">
											{formData.fly.appName || selectedApp}
										</p>
										<p className="text-muted-foreground text-xs">
											Region:{" "}
											{FLY_REGIONS.find((r) => r.value === formData.fly.region)
												?.label || formData.fly.region}{" "}
											| Memory: {formData.fly.memory} | Port:{" "}
											{formData.container.port}
										</p>
									</div>
									<Badge variant={isDeployed ? "default" : "secondary"}>
										{isDeployed ? "Deployed" : "Not Deployed"}
									</Badge>
								</CardContent>
							</Card>
						)}

						{isEnabled && (
							<Card>
								<CardHeader>
									<CardTitle className="text-base">
										Configuration Summary
									</CardTitle>
								</CardHeader>
								<CardContent className="space-y-3">
									<div className="grid gap-3 sm:grid-cols-2">
										<div className="rounded-lg border border-border bg-secondary/30 p-3">
											<p className="text-muted-foreground text-xs">
												Container Type
											</p>
											<p className="font-medium text-foreground text-sm">
												{CONTAINER_TYPES.find(
													(t) => t.value === formData.container.type,
												)?.label || formData.container.type}
											</p>
										</div>
										<div className="rounded-lg border border-border bg-secondary/30 p-3">
											<p className="text-muted-foreground text-xs">Auto Stop</p>
											<p className="font-medium text-foreground text-sm capitalize">
												{formData.fly.autoStop}
											</p>
										</div>
										<div className="rounded-lg border border-border bg-secondary/30 p-3">
											<p className="text-muted-foreground text-xs">
												AWS Integration
											</p>
											<p className="font-medium text-foreground text-sm">
												{formData.container.aws.enable
													? "Enabled"
													: "Disabled"}
											</p>
										</div>
										<div className="rounded-lg border border-border bg-secondary/30 p-3">
											<p className="text-muted-foreground text-xs">
												Min Machines
											</p>
											<p className="font-medium text-foreground text-sm">
												{formData.fly.minMachines}
											</p>
										</div>
									</div>
								</CardContent>
							</Card>
						)}
					</TabsContent>

					{/* Configure Tab */}
					<TabsContent className="mt-6 space-y-4" value="configure">
						<Card>
							<CardHeader>
								<CardTitle className="text-base">
									Deployment Configuration
								</CardTitle>
								<CardDescription>
									Configure Fly.io deployment for {selectedApp}
								</CardDescription>
							</CardHeader>
							<CardContent className="space-y-6">
								{/* Enable Toggle */}
								<SwitchField
									label="Enable Deployment"
									description="Enable Fly.io deployment for this app"
								>
									<Switch
										checked={formData.enable}
										onCheckedChange={(checked) => updateField("enable", checked)}
									/>
								</SwitchField>

								{formData.enable && (
									<>
										{/* Fly.io Settings */}
										<FieldGroup
											title="Fly.io Settings"
											description="Configure Fly.io app settings"
										>
											<FieldRow>
												<Field label="App Name">
													<Input
														value={formData.fly.appName}
														onChange={(e) =>
															updateFlyField("appName", e.target.value)
														}
														placeholder={selectedApp}
													/>
												</Field>
												<Field label="Region">
													<Select
														value={formData.fly.region}
														onValueChange={(v) => updateFlyField("region", v)}
													>
														<SelectTrigger>
															<SelectValue placeholder="Select region" />
														</SelectTrigger>
														<SelectContent>
															{FLY_REGIONS.map((region) => (
																<SelectItem
																	key={region.value}
																	value={region.value}
																>
																	{region.label}
																</SelectItem>
															))}
														</SelectContent>
													</Select>
												</Field>
											</FieldRow>

											<FieldRow>
												<Field label="Memory">
													<Select
														value={formData.fly.memory}
														onValueChange={(v) => updateFlyField("memory", v)}
													>
														<SelectTrigger>
															<SelectValue placeholder="Select memory" />
														</SelectTrigger>
														<SelectContent>
															{MEMORY_OPTIONS.map((mem) => (
																<SelectItem key={mem} value={mem}>
																	{mem}
																</SelectItem>
															))}
														</SelectContent>
													</Select>
												</Field>
												<Field label="Auto Stop">
													<Select
														value={formData.fly.autoStop}
														onValueChange={(v) =>
															updateFlyField(
																"autoStop",
																v as "off" | "stop" | "suspend",
															)
														}
													>
														<SelectTrigger>
															<SelectValue placeholder="Select behavior" />
														</SelectTrigger>
														<SelectContent>
															<SelectItem value="off">Off</SelectItem>
															<SelectItem value="stop">Stop</SelectItem>
															<SelectItem value="suspend">Suspend</SelectItem>
														</SelectContent>
													</Select>
												</Field>
											</FieldRow>

											<Field label="Minimum Machines">
												<Input
													type="number"
													min={0}
													value={formData.fly.minMachines}
													onChange={(e) =>
														updateFlyField(
															"minMachines",
															parseInt(e.target.value) || 0,
														)
													}
												/>
											</Field>
										</FieldGroup>

										{/* Container Settings */}
										<FieldGroup
											title="Container Settings"
											description="Configure container build and runtime"
										>
											<FieldRow>
												<Field label="Container Type">
													<Select
														value={formData.container.type}
														onValueChange={(v) =>
															updateContainerField(
																"type",
																v as DeploymentConfig["container"]["type"],
															)
														}
													>
														<SelectTrigger>
															<SelectValue placeholder="Select type" />
														</SelectTrigger>
														<SelectContent>
															{CONTAINER_TYPES.map((type) => (
																<SelectItem key={type.value} value={type.value}>
																	{type.label}
																</SelectItem>
															))}
														</SelectContent>
													</Select>
												</Field>
												<Field label="Port">
													<Input
														type="number"
														value={formData.container.port}
														onChange={(e) =>
															updateContainerField(
																"port",
																parseInt(e.target.value) || 3000,
															)
														}
													/>
												</Field>
											</FieldRow>

											{formData.container.type === "custom" && (
												<Field
													label="Build Command"
													description="Custom build command to run"
												>
													<Input
														value={formData.container.buildCommand || ""}
														onChange={(e) =>
															updateContainerField(
																"buildCommand",
																e.target.value || null,
															)
														}
														placeholder="npm run build"
													/>
												</Field>
											)}
										</FieldGroup>

										{/* AWS Integration */}
										<FieldGroup
											title="AWS Integration"
											description="Configure AWS credentials via Fly OIDC"
										>
											<SwitchField
												label="Enable AWS OIDC"
												description="Get AWS credentials via Fly.io OIDC"
											>
												<Switch
													checked={formData.container.aws.enable}
													onCheckedChange={(checked) =>
														updateAwsField("enable", checked)
													}
												/>
											</SwitchField>

											{formData.container.aws.enable && (
												<Field
													label="Chamber Service"
													description={
														isChamber && chamberServicePrefix
															? `Auto-derived from variables backend: ${chamberServicePrefix}/{stage}`
															: "Service path for Chamber secrets (e.g., myapp/prod)"
													}
												>
													<Input
														value={formData.container.aws.chamberService || ""}
														onChange={(e) =>
															updateAwsField(
																"chamberService",
																e.target.value || null,
															)
														}
														placeholder={
															isChamber && chamberServicePrefix
																? `${chamberServicePrefix}/prod`
																: "myapp/prod"
														}
													/>
													{isChamber && chamberServicePrefix && !formData.container.aws.chamberService && (
														<p className="text-xs text-muted-foreground mt-1">
															Leave empty to auto-derive from the project's chamber service prefix.
														</p>
													)}
												</Field>
											)}
										</FieldGroup>
									</>
								)}
							</CardContent>
						</Card>
					</TabsContent>

					{/* Deploy Tab */}
					<TabsContent className="mt-6 space-y-4" value="deploy">
						<Card>
							<CardHeader>
								<CardTitle className="text-base">Deploy to Fly.io</CardTitle>
								<CardDescription>
									Run the deployment pipeline for {selectedApp}
								</CardDescription>
							</CardHeader>
							<CardContent className="space-y-4">
								{!isEnabled ? (
									<div className="rounded-lg border border-amber-500/50 bg-amber-500/10 p-4">
										<div className="flex items-center gap-3">
											<AlertCircle className="h-5 w-5 text-amber-500" />
											<p className="text-amber-700 dark:text-amber-300 text-sm">
												Deployment is not enabled for this app. Enable it in
												the Configure tab first.
											</p>
										</div>
									</div>
								) : (
									<>
										{hasChanges && (
											<div className="rounded-lg border border-amber-500/50 bg-amber-500/10 p-4">
												<div className="flex items-center gap-3">
													<AlertCircle className="h-5 w-5 text-amber-500" />
													<p className="text-amber-700 dark:text-amber-300 text-sm">
														You have unsaved changes. Save your configuration
														before deploying.
													</p>
												</div>
											</div>
										)}

										<FieldRow>
											<Field label="Stage">
												<Select
													value={deployStage}
													onValueChange={setDeployStage}
												>
													<SelectTrigger>
														<SelectValue placeholder="Select stage" />
													</SelectTrigger>
													<SelectContent>
														<SelectItem value="dev">Development</SelectItem>
														<SelectItem value="staging">Staging</SelectItem>
														<SelectItem value="prod">Production</SelectItem>
													</SelectContent>
												</Select>
											</Field>
										</FieldRow>

										<div className="flex flex-wrap gap-2">
											<Button
												variant="outline"
												disabled={isDeploying || hasChanges}
												onClick={() => handleDeployStep("clean")}
												className="gap-2"
											>
												<Trash2 className="h-4 w-4" />
												Clean
											</Button>
											<Button
												variant="outline"
												disabled={isDeploying || hasChanges}
												onClick={() => handleDeployStep("build")}
												className="gap-2"
											>
												<Settings className="h-4 w-4" />
												Build
											</Button>
											<Button
												variant="outline"
												disabled={isDeploying || hasChanges}
												onClick={() => handleDeployStep("push")}
												className="gap-2"
											>
												<Cloud className="h-4 w-4" />
												Push
											</Button>
										</div>

										<div className="border-t border-border pt-4">
											<Button
												disabled={isDeploying || hasChanges}
												onClick={() => handleDeployStep("full")}
												className="gap-2 w-full sm:w-auto"
											>
												{isDeploying ? (
													<Loader2 className="h-4 w-4 animate-spin" />
												) : (
													<Play className="h-4 w-4" />
												)}
												{isDeploying ? "Deploying..." : "Deploy to Fly.io"}
											</Button>
										</div>
									</>
								)}
							</CardContent>
						</Card>
					</TabsContent>

					{/* Logs Tab */}
					<TabsContent className="mt-6 space-y-4" value="logs">
						<Card>
							<CardHeader className="flex flex-row items-center justify-between">
								<CardTitle className="text-base">Deployment Logs</CardTitle>
								<Button
									size="sm"
									variant="outline"
									onClick={() => setDeployOutput("")}
									className="gap-2"
								>
									<RefreshCw className="h-4 w-4" />
									Clear
								</Button>
							</CardHeader>
							<CardContent>
								{deployOutput ? (
									<pre className="max-h-96 overflow-auto rounded-lg border border-border bg-secondary/50 p-4 font-mono text-xs text-muted-foreground whitespace-pre-wrap">
										{deployOutput}
									</pre>
								) : (
									<p className="text-muted-foreground text-sm">
										No deployment logs yet. Run a deployment to see output here.
									</p>
								)}
							</CardContent>
						</Card>
					</TabsContent>
				</Tabs>
			</div>
		</TooltipProvider>
	);
}
