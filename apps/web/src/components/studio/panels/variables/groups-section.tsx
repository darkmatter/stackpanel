"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import {
	AlertTriangle,
	CheckCircle2,
	Clock,
	Copy,
	Key,
	Loader2,
	RefreshCw,
	Shield,
	XCircle,
} from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import { toast } from "sonner";
import { useModuleHealth } from "@/lib/healthchecks/use-healthchecks";
import { RecipientsSection } from "./recipients-section";
import type { HealthStatus } from "@/lib/healthchecks/types";
import { useNixConfigQuery } from "@/lib/use-agent";
import { InitializeGroupDialog } from "./initialize-group-dialog";

interface GroupConfig {
	agePub?: string;
	ssmPath: string;
	ref: string;
}

interface GroupsData {
	[name: string]: GroupConfig;
}

/**
 * Get the SSM access status for a specific group from the SOPS module health data.
 * The check ID follows the pattern: sops-ssm-access-{groupName}
 */
function getGroupSsmStatus(
	sopsHealth: ReturnType<typeof useModuleHealth>["data"],
	groupName: string,
): { status: HealthStatus | null; message?: string; output?: string } {
	if (!sopsHealth?.checks) return { status: null };
	const check = sopsHealth.checks.find(
		(c) => c.checkId === `sops-ssm-access-${groupName}`,
	);
	if (!check) return { status: null };
	return {
		status: check.status,
		message: check.message ?? undefined,
		output: check.output ?? undefined,
	};
}

export function GroupsSection() {
	const { data: nixConfig, isLoading, refetch } = useNixConfigQuery();
	const [initializingGroup, setInitializingGroup] = useState<{
		name: string;
		ssmPath: string;
		isReinitialize: boolean;
	} | null>(null);

	// Fetch SOPS module health to get per-group SSM access status
	const { data: sopsHealth, runChecks: runSopsChecks } =
		useModuleHealth("sops");

	// Extract groups from the nix config
	const groups: GroupsData = useMemo(() => {
		if (!nixConfig?.config) return {};
		const secrets = nixConfig.config.secrets as
			| { groups?: GroupsData }
			| undefined;
		return secrets?.groups ?? {};
	}, [nixConfig]);

	const groupEntries = useMemo(() => {
		return Object.entries(groups).sort(([a], [b]) => a.localeCompare(b));
	}, [groups]);

	const initializedCount = useMemo(() => {
		return groupEntries.filter(([, g]) => g.agePub && g.agePub !== "")
			.length;
	}, [groupEntries]);

	const handleCopyPublicKey = useCallback((key: string) => {
		navigator.clipboard.writeText(key);
		toast.success("Public key copied to clipboard");
	}, []);

	if (isLoading) {
		return (
			<Card>
				<CardContent className="flex items-center justify-center py-12">
					<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
				</CardContent>
			</Card>
		);
	}

	if (groupEntries.length === 0) {
		return (
			<div className="space-y-4">
				<div>
					<h3 className="text-lg font-medium mb-1">
						Secrets Groups
					</h3>
					<p className="text-sm text-muted-foreground">
						Access control boundaries for secrets encryption.
					</p>
				</div>
				<Card>
					<CardContent className="py-10 text-center text-muted-foreground">
						<Shield className="mx-auto h-10 w-10 text-muted-foreground/50" />
						<p className="mt-3 text-sm">No groups configured</p>
						<p className="mt-1 text-xs text-muted-foreground">
							Add groups in{" "}
							<code className="bg-muted px-1 py-0.5 rounded text-xs">
								stackpanel.secrets.groups
							</code>
						</p>
					</CardContent>
				</Card>
			</div>
		);
	}

	return (
		<div className="space-y-4">
			<div className="flex items-center justify-between">
				<div>
					<h3 className="text-lg font-medium mb-1">
						Secrets Groups
					</h3>
					<p className="text-sm text-muted-foreground">
						{initializedCount} of {groupEntries.length} group
						{groupEntries.length !== 1 ? "s" : ""} initialized
					</p>
				</div>
				<div className="flex items-center gap-1">
					<Button
						variant="ghost"
						size="sm"
						onClick={() => runSopsChecks()}
						className="h-8 px-2 text-xs"
						title="Re-run SSM access checks"
					>
						<Shield className="h-3.5 w-3.5 mr-1" />
						Check SSM
					</Button>
					<Button
						variant="ghost"
						size="sm"
						onClick={() => refetch()}
						className="h-8 px-2"
					>
						<RefreshCw className="h-3.5 w-3.5" />
					</Button>
				</div>
			</div>

			<div className="space-y-3">
				{groupEntries.map(([name, group]) => {
					const isInitialized =
						group.agePub != null && group.agePub !== "";
					const ssmStatus = getGroupSsmStatus(sopsHealth, name);
					const ssmAccessible =
						ssmStatus.status === "HEALTH_STATUS_HEALTHY";
					const ssmChecked = ssmStatus.status !== null;
					return (
						<Card
							key={name}
							className={
								isInitialized
									? "border-green-500/20"
									: "border-amber-500/20"
							}
						>
							<CardContent className="p-4">
								<div className="flex items-start justify-between gap-4">
									<div className="flex items-start gap-3 min-w-0">
										<div
											className={`mt-0.5 rounded-full p-1.5 ${
												isInitialized
													? "bg-green-500/10 text-green-600 dark:text-green-400"
													: "bg-amber-500/10 text-amber-600 dark:text-amber-400"
											}`}
										>
											{isInitialized ? (
												<CheckCircle2 className="h-4 w-4" />
											) : (
												<Clock className="h-4 w-4" />
											)}
										</div>
										<div className="min-w-0 space-y-2">
											<div className="flex items-center gap-2 flex-wrap">
												<code className="text-sm font-semibold font-mono">
													{name}
												</code>
												<Badge
													variant={
														isInitialized
															? "outline"
															: "secondary"
													}
													className={
														isInitialized
															? "border-green-500/30 text-green-600 dark:text-green-400 text-[10px]"
															: "text-[10px]"
													}
												>
													{isInitialized
														? "Initialized"
														: "Pending"}
												</Badge>
												{ssmChecked && (
													<Badge
														variant="outline"
														className={
															ssmAccessible
																? "border-green-500/30 text-green-600 dark:text-green-400 text-[10px]"
																: "border-red-500/30 text-red-600 dark:text-red-400 text-[10px]"
														}
													>
														{ssmAccessible ? (
															<CheckCircle2 className="h-3 w-3 mr-1" />
														) : (
															<XCircle className="h-3 w-3 mr-1" />
														)}
														SSM
													</Badge>
												)}
											</div>

											<div className="space-y-1.5">
												<div>
													<p className="text-[10px] font-medium text-muted-foreground uppercase tracking-wider">
														SSM Path
													</p>
													<div className="flex items-center gap-1.5">
														<code className="text-xs font-mono text-muted-foreground break-all">
															{group.ssmPath}
														</code>
														{ssmChecked && !ssmAccessible && (
															<span
																className="shrink-0"
																title={
																	ssmStatus.output ??
																	"SSM parameter not accessible"
																}
															>
																<AlertTriangle className="h-3 w-3 text-red-500" />
															</span>
														)}
													</div>
													{ssmChecked && !ssmAccessible && ssmStatus.output && (
														<p className="text-[10px] text-red-500 mt-0.5">
															{ssmStatus.output.split("\n")[0]}
														</p>
													)}
												</div>

												{isInitialized && (
													<div>
														<p className="text-[10px] font-medium text-muted-foreground uppercase tracking-wider">
															Public Key
														</p>
														<div className="flex items-center gap-1.5">
															<code className="text-xs font-mono text-muted-foreground break-all">
																{group.agePub!.length >
																50
																	? `${group.agePub!.slice(0, 25)}...${group.agePub!.slice(-15)}`
																	: group.agePub}
															</code>
															<Button
																variant="ghost"
																size="sm"
																className="h-5 w-5 p-0 shrink-0"
																onClick={() =>
																	handleCopyPublicKey(
																		group.agePub!,
																	)
																}
															>
																<Copy className="h-3 w-3" />
															</Button>
														</div>
													</div>
												)}

												<div>
													<p className="text-[10px] font-medium text-muted-foreground uppercase tracking-wider">
														Vals Reference
													</p>
													<code className="text-xs font-mono text-muted-foreground break-all">
														{group.ref}
													</code>
												</div>
											</div>
										</div>
									</div>

									<div className="shrink-0">
										{isInitialized ? (
											<Button
												variant="outline"
												size="sm"
												className="h-7 text-xs"
												onClick={() =>
													setInitializingGroup({
														name,
														ssmPath:
															group.ssmPath,
														isReinitialize: true,
													})
												}
											>
												<RefreshCw className="h-3 w-3 mr-1" />
												Re-init
											</Button>
										) : (
											<Button
												size="sm"
												className="h-7 text-xs"
												onClick={() =>
													setInitializingGroup({
														name,
														ssmPath:
															group.ssmPath,
														isReinitialize: false,
													})
												}
											>
												<Key className="h-3 w-3 mr-1" />
												Initialize
											</Button>
										)}
									</div>
								</div>
							</CardContent>
						</Card>
					);
				})}
			</div>

			{/* Info box */}
			<div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4 space-y-2">
				<h4 className="text-sm font-medium text-blue-600 dark:text-blue-400">
					How groups work
				</h4>
				<ul className="text-sm text-muted-foreground space-y-1 list-disc ml-4">
					<li>
						Each group has an AGE keypair. The private key is stored
						in AWS SSM.
					</li>
					<li>
						Secrets encrypted to a group can only be decrypted by
						users with IAM access to that SSM parameter.
					</li>
					<li>
						Use groups like{" "}
						<code className="bg-muted px-1 py-0.5 rounded text-xs">
							dev
						</code>{" "}
						and{" "}
						<code className="bg-muted px-1 py-0.5 rounded text-xs">
							prod
						</code>{" "}
						to restrict who can access production secrets.
					</li>
				</ul>
			</div>

			{/* Initialize Group Dialog */}
			{initializingGroup && (
				<InitializeGroupDialog
					groupName={initializingGroup.name}
					ssmPath={initializingGroup.ssmPath}
					isReinitialize={initializingGroup.isReinitialize}
					open={!!initializingGroup}
					onOpenChange={(open) => {
						if (!open) setInitializingGroup(null);
					}}
					onSuccess={() => {
						refetch();
						setInitializingGroup(null);
					}}
			/>
		)}

		{/* Recipients section */}
		<RecipientsSection />
	</div>
);
}
