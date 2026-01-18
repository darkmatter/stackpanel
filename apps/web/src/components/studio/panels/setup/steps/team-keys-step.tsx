"use client";

import { Button } from "@ui/button";
import { CheckCircle2, DownloadCloudIcon, Loader2, Users } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useAgentClient } from "@/lib/agent-provider";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

interface SyncResult {
	collaborators: string[];
	count: number;
}

/**
 * Parse the output from `stackpanel user sync` to extract collaborator names.
 * Expected output format varies, but typically includes usernames.
 */
function parseSyncOutput(stdout: string): SyncResult {
	const lines = stdout.trim().split("\n");
	const collaborators: string[] = [];

	for (const line of lines) {
		const match = line.match(/^\s*(?:•|✓|-)\s*([a-zA-Z0-9_-]+)\b/);
		if (match?.[1]) {
			collaborators.push(match[1]);
		}
	}

	return {
		collaborators,
		count: collaborators.length,
	};
}

export function TeamKeysStep() {
	const { expandedStep, setExpandedStep, usersConfigured, token } =
		useSetupContext();
	const agentClient = useAgentClient();
	const [isSyncing, setIsSyncing] = useState(false);
	const [syncResult, setSyncResult] = useState<SyncResult | null>(null);

	const step: SetupStep = {
		id: "team-keys",
		title: "Github Team Sync",
		description: "Sync public keys from Github collaborators",
		status: usersConfigured || syncResult ? "complete" : "optional",
		required: false,
		icon: <Users className="h-5 w-5" />,
	};

	const handleSync = async () => {
		if (!token) {
			toast.error("Not connected to agent");
			return;
		}

		setIsSyncing(true);
		try {
			const client = agentClient;
			const result = await client.exec({
				command: "stackpanel",
				args: ["user", "sync"],
			});

			if (result.exit_code === 0) {
				const parsed = parseSyncOutput(result.stdout);
				setSyncResult(parsed);
				if (parsed.count > 0) {
					toast.success(
						`Synced ${parsed.count} collaborator${parsed.count === 1 ? "" : "s"}`,
					);
				} else {
					toast.success("Team keys synced successfully");
				}
			} else {
				toast.error(`Sync failed: ${result.stderr || result.stdout}`);
			}
		} catch (err) {
			toast.error(err instanceof Error ? err.message : "Failed to sync");
		} finally {
			setIsSyncing(false);
		}
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "team-keys"}
			onToggle={() =>
				setExpandedStep(expandedStep === "team-keys" ? null : "team-keys")
			}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					Enable this to have a Github Action automatically re-encrypt secrets
					with the public keys of your team members.
				</p>

				<div className="rounded-lg border p-4 space-y-3">
					<h4 className="font-medium text-sm">How it works:</h4>
					<ol className="list-decimal list-inside space-y-2 text-sm text-muted-foreground">
						<li>
							Public keys are fetched from Github repository collaborators
						</li>
						<li>
							Secrets are re-encrypted with all keys using a Github Action
						</li>
						<li>
							The re-encrypted secrets are committed back to the repository by
							the Github Action
						</li>
						<li>
							Click "Sync Now" to fetch the initial set of collaborators and
							re-encrypt secrets here.
						</li>
					</ol>
				</div>

				{syncResult && (
					<div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3 space-y-2">
						<p className="text-sm text-emerald-700 dark:text-emerald-300 flex items-center gap-2">
							<CheckCircle2 className="h-4 w-4" />
							{syncResult.count > 0
								? `Synced ${syncResult.count} collaborator${syncResult.count === 1 ? "" : "s"}`
								: "Team keys synced successfully"}
						</p>
						{syncResult.collaborators.length > 0 && (
							<div className="flex flex-wrap gap-1.5 mt-2">
								{syncResult.collaborators.slice(0, 8).map((name) => (
									<span
										key={name}
										className="inline-flex items-center px-2 py-0.5 rounded-md bg-emerald-500/20 text-xs font-medium text-emerald-700 dark:text-emerald-300"
									>
										@{name}
									</span>
								))}
								{syncResult.collaborators.length > 8 && (
									<span className="text-xs text-muted-foreground">
										+{syncResult.collaborators.length - 8} more
									</span>
								)}
							</div>
						)}
					</div>
				)}

				<Button
					variant="outline"
					onClick={handleSync}
					disabled={isSyncing || !token}
				>
					{isSyncing ? (
						<Loader2 className="h-4 w-4 mr-2 animate-spin" />
					) : (
						<DownloadCloudIcon className="h-4 w-4 mr-2" />
					)}
					{isSyncing ? "Syncing..." : "Sync Now"}
				</Button>
			</div>
		</StepCard>
	);
}
