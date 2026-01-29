"use client";

import React from "react";
import { Link } from "@tanstack/react-router";
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
	CheckCircle2,
	Cloud,
	CloudOff,
	Key,
	Loader2,
	RefreshCw,
	Save,
	Settings,
	Shield,
} from "lucide-react";
import { useAgentContext } from "@/lib/agent-provider";
import {
	AWS_REGIONS,
	OIDC_PROVIDERS,
	OutputRow,
	ResourceRow,
	StatusCard,
	useSSTConfig,
} from "./infra";
import { PanelHeader } from "./shared/panel-header";
import { CommandRunner } from "../command-runner";

export function InfraPanel() {
	const { isConnected } = useAgentContext();
	const {
		formData,
		hasChanges,
		isSaving,
		updateField,
		updateNestedField,
		updateOidcProviderField,
		handleSave,
		status,
		outputs,
		resources,
		isLoading,
		error,
		deployStage,
		setDeployStage,
		loadStatus,
		currentProvider,
	} = useSSTConfig();

	const copyToClipboard = (text: string) => {
		navigator.clipboard.writeText(text);
	};

	// Not connected state
	if (!isConnected) {
		return (
			<TooltipProvider>
				<div className="space-y-6">
					<PanelHeader
						title="Infrastructure"
						description="AWS infrastructure provisioning with SST"
						guideKey="services"
						helpTooltip="Infrastructure guide"
					/>
					<Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
						<CardContent className="flex flex-col items-center justify-center gap-4 p-8">
							<CloudOff className="h-12 w-12 text-muted-foreground" />
							<div className="text-center">
								<p className="font-medium text-foreground">
									Agent Not Connected
								</p>
								<p className="text-muted-foreground text-sm">
									Connect to the stackpanel agent to manage infrastructure.
								</p>
							</div>
						</CardContent>
					</Card>
				</div>
			</TooltipProvider>
		);
	}

	// Loading state
	if (isLoading) {
		return (
			<TooltipProvider>
				<div className="space-y-6">
					<PanelHeader
						title="Infrastructure"
						description="AWS infrastructure provisioning with SST"
						guideKey="services"
						helpTooltip="Infrastructure guide"
					/>
					<div className="flex items-center justify-center py-12">
						<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
					</div>
				</div>
			</TooltipProvider>
		);
	}

	const isConfigured = formData.enable ?? false;
	const isDeployed = status?.deployed ?? false;

	return (
		<TooltipProvider>
			<div className="space-y-6">
				<PanelHeader
					title="Infrastructure"
					description="AWS infrastructure provisioning with SST"
					guideKey="services"
					helpTooltip="Infrastructure guide"
					actions={
						hasChanges && (
							<Button
								onClick={handleSave}
								disabled={isSaving}
								className="gap-2"
							>
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

				{/* Status Cards */}
				<div className="grid gap-4 sm:grid-cols-3">
					<StatusCard
						icon={Settings}
						label="Enabled"
						value={isConfigured ? "Yes" : "No"}
						active={isConfigured}
					/>
					<StatusCard
						icon={Cloud}
						label="Deployed"
						value={isDeployed ? "Yes" : "No"}
						active={isDeployed}
					/>
					<StatusCard
						icon={Key}
						label="KMS Enabled"
						value={formData.kms?.enable ? "Yes" : "No"}
						active={formData.kms?.enable ?? false}
					/>
				</div>

				{/* Error Alert */}
				{error && (
					<Card className="border-destructive/50 bg-destructive/10">
						<CardContent className="flex items-center gap-3 p-4">
							<AlertCircle className="h-5 w-5 text-destructive" />
							<p className="text-destructive text-sm">{error}</p>
						</CardContent>
					</Card>
				)}

				{/* Tabs */}
				<Tabs defaultValue="status">
					<TabsList>
						<TabsTrigger value="status">Status</TabsTrigger>
						<TabsTrigger value="deploy">Deploy</TabsTrigger>
						<TabsTrigger value="outputs">Outputs</TabsTrigger>
						<TabsTrigger value="resources">Resources</TabsTrigger>
						<TabsTrigger value="configure">Configure</TabsTrigger>
					</TabsList>

					{/* Status Tab */}
					<TabsContent className="mt-6 space-y-4" value="status">
						<StatusTabContent
							formData={formData}
							status={status}
							outputs={outputs}
							isConfigured={isConfigured}
							isDeployed={isDeployed}
							currentProvider={currentProvider}
						/>
					</TabsContent>

					{/* Deploy Tab */}
					<TabsContent className="mt-6 space-y-4" value="deploy">
						<DeployTabContent
							isConfigured={isConfigured}
							isDeployed={isDeployed}
							hasChanges={hasChanges}
							deployStage={deployStage}
							setDeployStage={setDeployStage}
						/>
					</TabsContent>

					{/* Outputs Tab */}
					<TabsContent className="mt-6 space-y-4" value="outputs">
						<OutputsTabContent
							outputs={outputs}
							loadStatus={loadStatus}
							copyToClipboard={copyToClipboard}
						/>
					</TabsContent>

					{/* Resources Tab */}
					<TabsContent className="mt-6 space-y-4" value="resources">
						<ResourcesTabContent
							resources={resources}
							isDeployed={isDeployed}
							loadStatus={loadStatus}
						/>
					</TabsContent>

					{/* Configure Tab */}
					<TabsContent className="mt-6 space-y-4" value="configure">
						<ConfigureTabContent
							formData={formData}
							currentProvider={currentProvider}
							updateField={updateField}
							updateNestedField={updateNestedField}
							updateOidcProviderField={updateOidcProviderField}
						/>
					</TabsContent>
				</Tabs>
			</div>
		</TooltipProvider>
	);
}

// =============================================================================
// Tab Content Components
// =============================================================================

import type { SSTData, SSTResource, SSTStatus } from "./infra";

function StatusTabContent({
	formData,
	status,
	outputs,
	isConfigured,
	isDeployed,
	currentProvider,
}: {
	formData: SSTData;
	status: SSTStatus | null;
	outputs: Record<string, unknown>;
	isConfigured: boolean;
	isDeployed: boolean;
	currentProvider: string;
}) {
	if (!isConfigured) {
		return (
			<Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
				<CardContent className="p-6">
					<p className="font-medium text-foreground text-sm">
						SST is not enabled
					</p>
					<p className="text-muted-foreground text-xs mt-1">
						Enable SST in the Configure tab to provision AWS infrastructure.
					</p>
				</CardContent>
			</Card>
		);
	}

	return (
		<>
			<Card className="border-accent/20 bg-accent/5">
				<CardContent className="flex items-center gap-4 p-4">
					<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/20">
						<Shield className="h-5 w-5 text-accent" />
					</div>
					<div className="flex-1">
						<p className="font-medium text-foreground text-sm">
							{formData["project-name"] || "SST Project"}
						</p>
						<p className="text-muted-foreground text-xs">
							Region: {formData.region} | Provider:{" "}
							{OIDC_PROVIDERS.find((p) => p.value === currentProvider)?.label}
						</p>
					</div>
					<Badge variant={isDeployed ? "default" : "secondary"}>
						{isDeployed ? "Deployed" : "Not Deployed"}
					</Badge>
				</CardContent>
			</Card>

			<Card>
				<CardHeader>
					<CardTitle className="text-base">Configuration Details</CardTitle>
				</CardHeader>
				<CardContent className="space-y-3">
					<div className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3">
						<div>
							<p className="font-medium text-foreground text-sm">IAM Role</p>
							<code className="text-muted-foreground text-xs">
								{formData.iam?.["role-name"] || "(not set)"}
							</code>
						</div>
						{isDeployed && Boolean(outputs?.roleArn) && (
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								<span className="text-accent text-xs">Active</span>
							</div>
						)}
					</div>

					{formData.kms?.enable && (
						<div className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3">
							<div>
								<p className="font-medium text-foreground text-sm">KMS Key</p>
								<code className="text-muted-foreground text-xs">
									alias/{formData.kms?.alias || "(not set)"}
								</code>
							</div>
							{isDeployed && Boolean(outputs?.kmsKeyArn) && (
								<div className="flex items-center gap-2">
									<CheckCircle2 className="h-4 w-4 text-accent" />
									<span className="text-accent text-xs">Active</span>
								</div>
							)}
						</div>
					)}

					<div className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3">
						<div>
							<p className="font-medium text-foreground text-sm">Config Path</p>
							<code className="text-muted-foreground text-xs">
								{formData["config-path"] || "(not set)"}
							</code>
						</div>
						{status?.configValid && (
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								<span className="text-accent text-xs">Valid</span>
							</div>
						)}
					</div>
				</CardContent>
			</Card>
		</>
	);
}

function DeployTabContent({
	isConfigured,
	isDeployed,
	hasChanges,
	deployStage,
	setDeployStage,
}: {
	isConfigured: boolean;
	isDeployed: boolean;
	hasChanges: boolean;
	deployStage: string;
	setDeployStage: (stage: string) => void;
}) {
	return (
		<Card>
			<CardHeader>
				<CardTitle className="text-base">Deploy Infrastructure</CardTitle>
				<CardDescription>
					Deploy or remove AWS infrastructure for your project
				</CardDescription>
			</CardHeader>
			<CardContent className="space-y-4">
				{hasChanges && (
					<Card className="border-amber-500/50 bg-amber-500/10">
						<CardContent className="flex items-center gap-3 p-4">
							<AlertCircle className="h-5 w-5 text-amber-500" />
							<p className="text-amber-700 dark:text-amber-300 text-sm">
								You have unsaved changes. Save your configuration before
								deploying.
							</p>
						</CardContent>
					</Card>
				)}

				<FieldRow>
					<Field label="Stage">
						<Select value={deployStage} onValueChange={setDeployStage}>
							<SelectTrigger>
								<SelectValue placeholder="Select stage" />
							</SelectTrigger>
							<SelectContent>
								<SelectItem value="dev">Development</SelectItem>
								<SelectItem value="staging">Staging</SelectItem>
								<SelectItem value="production">Production</SelectItem>
							</SelectContent>
						</Select>
					</Field>
					<div className="flex items-end gap-2">
						<CommandRunner
							command="sst"
							args={["deploy", "--stage", deployStage]}
							label="Deploy"
							description={`Deploy SST infrastructure to ${deployStage}`}
							disabled={!isConfigured || hasChanges}
							variant="default"
						/>
						{isDeployed && (
							<CommandRunner
								command="sst"
								args={["remove", "--stage", deployStage]}
								label="Remove"
								description={`Remove SST infrastructure from ${deployStage}`}
								variant="outline"
							/>
						)}
					</div>
				</FieldRow>

				{/* Info about CLI commands */}
				<div className="rounded-lg border border-border bg-secondary/30 p-4">
					<p className="text-muted-foreground text-sm">
						You can also run these commands from your terminal:
					</p>
					<div className="mt-2 space-y-1 font-mono text-xs">
						<div className="text-muted-foreground">
							<span className="text-accent">$</span> sst deploy --stage {deployStage}
						</div>
						<div className="text-muted-foreground">
							<span className="text-accent">$</span> sst remove --stage {deployStage}
						</div>
					</div>
				</div>
			</CardContent>
		</Card>
	);
}

function OutputsTabContent({
	outputs,
	loadStatus,
	copyToClipboard,
}: {
	outputs: Record<string, unknown>;
	loadStatus: () => Promise<void>;
	copyToClipboard: (text: string) => void;
}) {
	return (
		<Card>
			<CardHeader className="flex flex-row items-center justify-between">
				<CardTitle className="text-base">Stack Outputs</CardTitle>
				<Button
					onClick={loadStatus}
					size="sm"
					variant="outline"
					className="gap-2"
				>
					<RefreshCw className="h-4 w-4" />
					Refresh
				</Button>
			</CardHeader>
			<CardContent>
				{Object.keys(outputs).length === 0 ? (
					<p className="text-muted-foreground text-sm">
						No outputs available. Deploy infrastructure to see outputs.
					</p>
				) : (
					<div className="space-y-3">
						{Object.entries(outputs).map(([key, value]) => (
							<OutputRow
								key={key}
								name={key}
								value={value}
								onCopy={copyToClipboard}
							/>
						))}
					</div>
				)}
			</CardContent>
		</Card>
	);
}

function ResourcesTabContent({
	resources,
	isDeployed,
	loadStatus,
}: {
	resources: SSTResource[];
	isDeployed: boolean;
	loadStatus: () => Promise<void>;
}) {
	return (
		<Card>
			<CardHeader className="flex flex-row items-center justify-between">
				<CardTitle className="text-base">Deployed Resources</CardTitle>
				<Button
					onClick={loadStatus}
					size="sm"
					variant="outline"
					className="gap-2"
				>
					<RefreshCw className="h-4 w-4" />
					Refresh
				</Button>
			</CardHeader>
			<CardContent>
				{!isDeployed ? (
					<p className="text-muted-foreground text-sm">
						No resources deployed yet. Deploy infrastructure to see resources.
					</p>
				) : resources.length === 0 ? (
					<p className="text-muted-foreground text-sm">
						No resources found. Try refreshing.
					</p>
				) : (
					<div className="space-y-3">
						{resources.map((resource, i) => (
							<ResourceRow key={`${resource.urn}-${i}`} resource={resource} />
						))}
					</div>
				)}
			</CardContent>
		</Card>
	);
}

function ConfigureTabContent({
	formData,
	currentProvider,
	updateField,
	updateNestedField,
	updateOidcProviderField,
}: {
	formData: SSTData;
	currentProvider: string;
	updateField: <K extends keyof SSTData>(key: K, value: SSTData[K]) => void;
	updateNestedField: (
		parent: "kms" | "oidc" | "iam",
		key: string,
		value: unknown,
	) => void;
	updateOidcProviderField: (
		provider: "github-actions" | "flyio" | "roles-anywhere",
		key: string,
		value: string,
	) => void;
}) {
	return (
		<>
			{/* Note pointing to Setup */}
			<div className="rounded-lg border border-blue-500/20 bg-blue-500/10 p-4">
				<p className="text-sm text-blue-700 dark:text-blue-300 flex items-center gap-2">
					<Settings className="h-4 w-4" />
					<span>
						For initial setup, use the{" "}
						<Link
							to="/studio/setup"
							className="underline font-medium hover:text-blue-500"
						>
							Project Setup wizard
						</Link>{" "}
						which provides guided configuration with inherited defaults.
					</span>
				</p>
			</div>

			<Card>
				<CardHeader>
					<CardTitle className="text-base">SST Configuration</CardTitle>
					<CardDescription>
						Advanced configuration for AWS infrastructure provisioning
					</CardDescription>
				</CardHeader>
				<CardContent className="space-y-6">
					{/* Enable Toggle */}
					<SwitchField
						label="Enable SST Infrastructure"
						description="Generate SST config for AWS infrastructure provisioning"
					>
						<Switch
							checked={formData.enable ?? false}
							onCheckedChange={(checked) => updateField("enable", checked)}
						/>
					</SwitchField>

					{formData.enable && (
						<>
							{/* Basic Settings */}
							<FieldRow>
								<Field label="Project Name">
									<Input
										value={formData["project-name"] ?? ""}
										onChange={(e) =>
											updateField("project-name", e.target.value)
										}
										placeholder="my-project"
									/>
								</Field>
								<Field label="AWS Region">
									<Select
										value={formData.region ?? "us-west-2"}
										onValueChange={(value) => updateField("region", value)}
									>
										<SelectTrigger>
											<SelectValue placeholder="Select region" />
										</SelectTrigger>
										<SelectContent>
											{AWS_REGIONS.map((region) => (
												<SelectItem key={region} value={region}>
													{region}
												</SelectItem>
											))}
										</SelectContent>
									</Select>
								</Field>
							</FieldRow>

							<FieldRow>
								<Field label="AWS Account ID">
									<Input
										value={formData["account-id"] ?? ""}
										onChange={(e) => updateField("account-id", e.target.value)}
										placeholder="123456789012"
									/>
								</Field>
								<Field
									label="Config Path"
									description="Path to generated SST config file"
								>
									<Input
										value={formData["config-path"] ?? ""}
										onChange={(e) => updateField("config-path", e.target.value)}
										placeholder="packages/infra/sst.config.ts"
									/>
								</Field>
							</FieldRow>

							{/* KMS Settings */}
							<FieldGroup
								title="KMS Configuration"
								description="Encryption key settings"
							>
								<SwitchField
									label="Enable KMS Key"
									description="Create a KMS key for encrypting secrets"
								>
									<Switch
										checked={formData.kms?.enable ?? true}
										onCheckedChange={(checked) =>
											updateNestedField("kms", "enable", checked)
										}
									/>
								</SwitchField>

								{formData.kms?.enable && (
									<Field label="KMS Key Alias">
										<Input
											value={formData.kms?.alias ?? ""}
											onChange={(e) =>
												updateNestedField("kms", "alias", e.target.value)
											}
											placeholder="my-project-secrets"
										/>
									</Field>
								)}
							</FieldGroup>

							{/* OIDC Settings */}
							<FieldGroup
								title="OIDC Provider"
								description="Authentication for CI/CD access"
							>
								<Field label="Provider">
									<Select
										value={currentProvider}
										onValueChange={(value) =>
											updateNestedField("oidc", "provider", value)
										}
									>
										<SelectTrigger>
											<SelectValue placeholder="Select provider" />
										</SelectTrigger>
										<SelectContent>
											{OIDC_PROVIDERS.map((provider) => (
												<SelectItem key={provider.value} value={provider.value}>
													{provider.label}
												</SelectItem>
											))}
										</SelectContent>
									</Select>
								</Field>

								{currentProvider === "github-actions" && (
									<FieldRow>
										<Field label="GitHub Organization">
											<Input
												value={formData.oidc?.["github-actions"]?.org ?? ""}
												onChange={(e) =>
													updateOidcProviderField(
														"github-actions",
														"org",
														e.target.value,
													)
												}
												placeholder="my-org"
											/>
										</Field>
										<Field label="Repository" description="Use * for all repos">
											<Input
												value={formData.oidc?.["github-actions"]?.repo ?? "*"}
												onChange={(e) =>
													updateOidcProviderField(
														"github-actions",
														"repo",
														e.target.value,
													)
												}
												placeholder="*"
											/>
										</Field>
									</FieldRow>
								)}

								{currentProvider === "flyio" && (
									<FieldRow>
										<Field label="Fly.io Organization ID">
											<Input
												value={formData.oidc?.flyio?.["org-id"] ?? ""}
												onChange={(e) =>
													updateOidcProviderField(
														"flyio",
														"org-id",
														e.target.value,
													)
												}
												placeholder="my-org"
											/>
										</Field>
										<Field label="App Name" description="Use * for all apps">
											<Input
												value={formData.oidc?.flyio?.["app-name"] ?? "*"}
												onChange={(e) =>
													updateOidcProviderField(
														"flyio",
														"app-name",
														e.target.value,
													)
												}
												placeholder="*"
											/>
										</Field>
									</FieldRow>
								)}

								{currentProvider === "roles-anywhere" && (
									<Field label="Trust Anchor ARN">
										<Input
											value={
												formData.oidc?.["roles-anywhere"]?.[
													"trust-anchor-arn"
												] ?? ""
											}
											onChange={(e) =>
												updateOidcProviderField(
													"roles-anywhere",
													"trust-anchor-arn",
													e.target.value,
												)
											}
											placeholder="arn:aws:rolesanywhere:..."
										/>
									</Field>
								)}
							</FieldGroup>

							{/* IAM Settings */}
							<Field label="IAM Role Name">
								<Input
									value={formData.iam?.["role-name"] ?? ""}
									onChange={(e) =>
										updateNestedField("iam", "role-name", e.target.value)
									}
									placeholder="my-project-secrets-role"
								/>
							</Field>
						</>
					)}
				</CardContent>
			</Card>
		</>
	);
}
