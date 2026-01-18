"use client";

import { Button } from "@ui/button";
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
import { Check, CheckCircle2, Cloud, Key, Loader2, Shield } from "lucide-react";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import { AWS_REGIONS, OIDC_PROVIDERS, type SetupStep } from "../types";

export function InfrastructureStep() {
	const {
		expandedStep,
		setExpandedStep,
		projectName,
		githubRepo,
		sstData,
		sstFormData,
		setSstFormData,
		handleSaveSST,
		sstSaving,
	} = useSetupContext();

	// Extract org from github repo if available
	const githubOrg = githubRepo?.split("/")[0] || "";

	const step: SetupStep = {
		id: "infrastructure",
		title: "AWS Auto-Deployment",
		description:
			"Deploy KMS key and IAM roles for CI/CD secrets access (can replace AGE keys)",
		status: sstData?.enable ? "complete" : "optional",
		required: false,
		dependsOn: ["project-info"],
		icon: <Cloud className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "infrastructure"}
			onToggle={() =>
				setExpandedStep(
					expandedStep === "infrastructure" ? null : "infrastructure",
				)
			}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					Deploy AWS infrastructure for secrets management according to our
					convention:
					<table className="w-full mt-2 border-collapse">
						<thead>
							<tr className="border-b border-border">
								<th className="text-left h-8 items-center">Resource</th>
								<th className="text-left h-8 items-center ">Description</th>
							</tr>
						</thead>
						<tbody>
							{[
								{
									label: "IAM Role",
									code: `arn:aws:iam::${sstFormData["account-id"]}:role/${sstFormData.iam?.["role-name"]}`,
									description: "Role with access to the KMS key.",
								},
								{
									label: "KMS Key",
									code: `alias/my-key`,
									description:
										"Key that is used to encrypt and decrypt secrets.",
								},
								{
									label: "SST Configuration",
									code: `infra/sst/sst.config.ts`,
									description:
										"Configuration that is used to deploy the infrastructure.",
								},
							].map((item) => (
								<tr
									key={item.label}
									className="border-b border-border h-8 items-center"
								>
									<td className="text-[10px] whitespace-pre">
										<code>{item.code}</code>
									</td>
									<td className="text-xs">{item.description}</td>
								</tr>
							))}
						</tbody>
					</table>
				</p>

				<div className="space-y-4">
					{/* Enable toggle */}
					<div className="flex items-center justify-between p-4 rounded-lg border">
						<div className="space-y-0.5">
							<Label className="text-base font-medium">
								Enable AWS Infrastructure
							</Label>
							<p className="text-xs text-muted-foreground">
								Deploy IAM role and KMS key via SST
							</p>
						</div>
						<Switch
							checked={sstFormData.enable ?? false}
							onCheckedChange={(checked) =>
								setSstFormData({ ...sstFormData, enable: checked })
							}
						/>
					</div>

					{sstFormData.enable && (
						<div className="space-y-6 pt-2">
							{/* AWS Configuration */}
							<div className="space-y-4">
								<h4 className="font-medium flex items-center gap-2">
									<Cloud className="h-4 w-4" />
									AWS Configuration
								</h4>
								<div className="grid grid-cols-2 gap-4 pl-6">
									<div className="space-y-2">
										<Label>AWS Region</Label>
										<Select
											value={sstFormData.region || "us-west-2"}
											onValueChange={(value) =>
												setSstFormData({ ...sstFormData, region: value })
											}
										>
											<SelectTrigger>
												<SelectValue />
											</SelectTrigger>
											<SelectContent>
												{AWS_REGIONS.map((region) => (
													<SelectItem key={region.value} value={region.value}>
														{region.label}
													</SelectItem>
												))}
											</SelectContent>
										</Select>
									</div>

									<div className="space-y-2">
										<Label>AWS Account ID</Label>
										<Input
											value={sstFormData["account-id"] || ""}
											onChange={(e) =>
												setSstFormData({
													...sstFormData,
													"account-id": e.target.value,
												})
											}
											placeholder="123456789012"
											className="font-mono text-sm"
										/>
									</div>
								</div>
							</div>

							{/* OIDC Provider */}
							<div className="space-y-4">
								<h4 className="font-medium flex items-center gap-2">
									<Shield className="h-4 w-4" />
									CI/CD Authentication (OIDC)
								</h4>
								<div className="space-y-4 pl-6">
									<div className="space-y-2">
										<Label>OIDC Provider</Label>
										<Select
											value={sstFormData.oidc?.provider || "github-actions"}
											onValueChange={(value) =>
												setSstFormData({
													...sstFormData,
													oidc: { ...sstFormData.oidc, provider: value },
												})
											}
										>
											<SelectTrigger>
												<SelectValue />
											</SelectTrigger>
											<SelectContent>
												{OIDC_PROVIDERS.map((provider) => (
													<SelectItem
														key={provider.value}
														value={provider.value}
													>
														{provider.label}
													</SelectItem>
												))}
											</SelectContent>
										</Select>
										<p className="text-xs text-muted-foreground">
											{
												OIDC_PROVIDERS.find(
													(p) => p.value === sstFormData.oidc?.provider,
												)?.description
											}
										</p>
									</div>

									{/* GitHub Actions fields */}
									{sstFormData.oidc?.provider === "github-actions" && (
										<div className="space-y-4 rounded-lg border p-4 bg-muted/30">
											<div className="grid grid-cols-2 gap-4">
												<div className="space-y-2">
													<Label>GitHub Organization</Label>
													<Input
														value={
															sstFormData.oidc?.["github-actions"]?.org ||
															githubOrg
														}
														onChange={(e) =>
															setSstFormData({
																...sstFormData,
																oidc: {
																	...sstFormData.oidc,
																	"github-actions": {
																		...sstFormData.oidc?.["github-actions"],
																		org: e.target.value,
																	},
																},
															})
														}
														placeholder="your-org"
													/>
												</div>
												<div className="space-y-2">
													<Label>Repository</Label>
													<Input
														value={
															sstFormData.oidc?.["github-actions"]?.repo || "*"
														}
														onChange={(e) =>
															setSstFormData({
																...sstFormData,
																oidc: {
																	...sstFormData.oidc,
																	"github-actions": {
																		...sstFormData.oidc?.["github-actions"],
																		repo: e.target.value,
																	},
																},
															})
														}
														placeholder="* (all repos)"
													/>
												</div>
											</div>
										</div>
									)}
								</div>
							</div>

							{/* KMS Configuration */}
							<div className="space-y-4">
								<h4 className="font-medium flex items-center gap-2">
									<Key className="h-4 w-4" />
									KMS Key (for secrets encryption)
								</h4>
								<div className="space-y-4 pl-6">
									<div className="flex items-center justify-between p-3 rounded-lg border">
										<div>
											<Label>Create KMS Key</Label>
											<p className="text-xs text-muted-foreground">
												Deploy a KMS key for encrypting SOPS secrets
											</p>
										</div>
										<Switch
											checked={sstFormData.kms?.enable ?? true}
											onCheckedChange={(checked) =>
												setSstFormData({
													...sstFormData,
													kms: { ...sstFormData.kms, enable: checked },
												})
											}
										/>
									</div>

									{sstFormData.kms?.enable && (
										<div className="space-y-2">
											<Label>KMS Key Alias</Label>
											<Input
												value={sstFormData.kms?.alias || ""}
												onChange={(e) =>
													setSstFormData({
														...sstFormData,
														kms: { ...sstFormData.kms, alias: e.target.value },
													})
												}
												placeholder={`${projectName}-secrets`}
												className="font-mono text-sm"
											/>
										</div>
									)}
								</div>
							</div>

							{/* Actions */}
							<div className="pt-2 flex items-center gap-2">
								<Button onClick={handleSaveSST} disabled={sstSaving}>
									{sstSaving ? (
										<Loader2 className="h-4 w-4 animate-spin mr-2" />
									) : (
										<Check className="h-4 w-4 mr-2" />
									)}
									Save & Continue
								</Button>
							</div>

							{sstData?.enable && (
								<div className="rounded-lg bg-emerald-400/10 border border-emerald-500/20 p-3">
									<p className="text-sm text-emerald-700 dark:text-emerald-400 flex items-center gap-2">
										<CheckCircle2 className="h-4 w-4" />
										AWS Infrastructure configured. Deploy via the Infrastructure
										panel after setup.
									</p>
								</div>
							)}
						</div>
					)}

					{!sstFormData.enable && (
						<p className="text-sm text-muted-foreground">
							Skip this step if you prefer to use AGE keys only, or configure
							AWS later.
						</p>
					)}
				</div>
			</div>
		</StepCard>
	);
}
