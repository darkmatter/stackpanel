"use client";

import { Button } from "@ui/button";
import {
	CheckCircle2,
	Database,
	Loader2,
	Shield,
	XCircle,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { useAgentClient } from "@/lib/agent-provider";
import { useNixConfigQuery } from "@/lib/use-agent";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

interface GroupStatus {
	name: string;
	initialized: boolean;
	verified: boolean;
	verifying: boolean;
	initializing: boolean;
	error: string | null;
}

export function InitGroupsStep() {
	const { expandedStep, setExpandedStep, token, isChamber, goToStep } =
		useSetupContext();
	const agentClient = useAgentClient();
	const { data: nixConfig } = useNixConfigQuery();

	const [groups, setGroups] = useState<GroupStatus[]>([]);
	const [loading, setLoading] = useState(true);

	// Extract group names from nix config
	const configRoot = (nixConfig as Record<string, Record<string, unknown>>)
		?.config;
	const secretsConfig = configRoot?.secrets as
		| Record<string, unknown>
		| undefined;
	const groupsConfigMap = (secretsConfig?.groups ?? {}) as Record<
		string,
		Record<string, unknown>
	>;
	const groupNamesList = Object.keys(groupsConfigMap);
	const groupNamesKey = groupNamesList.join(",");

	// Check which groups are initialized
	const checkGroups = useCallback(async () => {
		if (!token || groupNamesList.length === 0) {
			setLoading(false);
			return;
		}

		setLoading(true);
		const statuses: GroupStatus[] = [];

		for (const name of groupNamesList) {
			const agePub = groupsConfigMap[name]?.["age-pub"] as string | undefined;
			statuses.push({
				name,
				initialized: !!agePub && agePub !== "",
				verified: false,
				verifying: false,
				initializing: false,
				error: null,
			});
		}

		setGroups(statuses);
		setLoading(false);
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [token, groupNamesKey]);

	useEffect(() => {
		checkGroups();
	}, [checkGroups]);

	const handleInitGroup = async (groupName: string) => {
		setGroups((prev) =>
			prev.map((g) =>
				g.name === groupName
					? { ...g, initializing: true, error: null }
					: g,
			),
		);

		try {
			const result = await agentClient.exec({
				command: "secrets:init-group",
				args: [groupName, "--yes", "--json", "--no-gh"],
			});

			if (result.exit_code === 0) {
				const data = JSON.parse(result.stdout);
				setGroups((prev) =>
					prev.map((g) =>
						g.name === groupName
							? { ...g, initialized: true, initializing: false }
							: g,
					),
				);
				toast.success(
					`Group "${groupName}" initialized (pub: ${(data.publicKey as string)?.slice(0, 16)}...)`,
				);
			} else {
				throw new Error(result.stderr || "Init failed");
			}
		} catch (err) {
			setGroups((prev) =>
				prev.map((g) =>
					g.name === groupName
						? {
								...g,
								initializing: false,
								error:
									err instanceof Error ? err.message : "Failed",
							}
						: g,
				),
			);
			toast.error(
				err instanceof Error
					? err.message
					: `Failed to initialize ${groupName}`,
			);
		}
	};

	const handleVerify = async (groupName: string) => {
		setGroups((prev) =>
			prev.map((g) =>
				g.name === groupName
					? { ...g, verifying: true, error: null }
					: g,
			),
		);

		try {
			const result = await agentClient.verifySecrets(groupName);
			setGroups((prev) =>
				prev.map((g) =>
					g.name === groupName
						? {
								...g,
								verified: result.success,
								verifying: false,
								error: result.success ? null : (String((result as unknown as Record<string, unknown>).error) || "Verification failed"),
							}
						: g,
				),
			);
			if (result.success) {
				toast.success(`Group "${groupName}" encrypt/decrypt verified`);
			} else {
				toast.error(`Verification failed for "${groupName}"`);
			}
		} catch (err) {
			setGroups((prev) =>
				prev.map((g) =>
					g.name === groupName
						? {
								...g,
								verifying: false,
								error:
									err instanceof Error ? err.message : "Failed",
							}
						: g,
				),
			);
		}
	};

	const allInitialized = groups.length > 0 && groups.every((g) => g.initialized);
	const anyVerified = groups.some((g) => g.verified);

	const step: SetupStep = {
		id: "init-groups",
		title: "Initialize Secret Groups",
		description: "Generate encryption keys for each environment",
		status: isChamber
			? "complete"
			: anyVerified
				? "complete"
				: allInitialized
					? "incomplete"
					: "incomplete",
		required: !isChamber,
		dependsOn: ["secrets-backend"],
		icon: <Shield className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "init-groups"}
			onToggle={() =>
				setExpandedStep(
					expandedStep === "init-groups" ? null : "init-groups",
				)
			}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					Each group (dev, prod, etc.) has its own AGE keypair. Initialize
					them here, then verify encrypt/decrypt works.
				</p>

				{loading ? (
					<div className="flex items-center gap-2 py-4">
						<Loader2 className="h-4 w-4 animate-spin" />
						<span className="text-sm text-muted-foreground">
							Loading groups...
						</span>
					</div>
				) : groups.length === 0 ? (
					<div className="rounded-lg border p-4">
						<p className="text-sm text-muted-foreground">
							No groups configured. Groups are defined in your{" "}
							<code>config.nix</code> under <code>secrets.groups</code>.
						</p>
					</div>
				) : (
					<div className="space-y-3">
						{groups.map((group) => (
							<div
								key={group.name}
								className="rounded-lg border p-4 flex items-center justify-between"
							>
								<div className="flex items-center gap-3">
									<Database className="h-4 w-4 text-muted-foreground" />
									<div>
										<p className="text-sm font-medium">{group.name}</p>
										<p className="text-xs text-muted-foreground">
											{group.verified ? (
												<span className="text-emerald-500 flex items-center gap-1">
													<CheckCircle2 className="h-3 w-3" />
													Verified
												</span>
											) : group.initialized ? (
												"Initialized - click Verify to test"
											) : (
												"Not initialized"
											)}
										</p>
										{group.error && (
											<p className="text-xs text-red-500 flex items-center gap-1 mt-1">
												<XCircle className="h-3 w-3" />
												{group.error}
											</p>
										)}
									</div>
								</div>
								<div className="flex items-center gap-2">
									{!group.initialized && (
										<Button
											size="sm"
											variant="outline"
											onClick={() => handleInitGroup(group.name)}
											disabled={group.initializing}
										>
											{group.initializing ? (
												<Loader2 className="h-3 w-3 animate-spin mr-1" />
											) : null}
											Initialize
										</Button>
									)}
									{group.initialized && !group.verified && (
										<Button
											size="sm"
											variant="outline"
											onClick={() => handleVerify(group.name)}
											disabled={group.verifying}
										>
											{group.verifying ? (
												<Loader2 className="h-3 w-3 animate-spin mr-1" />
											) : null}
											Verify
										</Button>
									)}
									{group.verified && (
										<CheckCircle2 className="h-5 w-5 text-emerald-500" />
									)}
								</div>
							</div>
						))}
					</div>
				)}

				{anyVerified && (
					<div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3">
						<p className="text-sm text-emerald-700 dark:text-emerald-300 flex items-center gap-2">
							<CheckCircle2 className="h-4 w-4" />
							Groups verified. You can now create secrets.
						</p>
					</div>
				)}

				{anyVerified && (
					<Button
						variant="outline"
						onClick={() => goToStep("team-access")}
					>
						Continue to Team Access
					</Button>
				)}
			</div>
		</StepCard>
	);
}
