/**
 * State management hook for Databases Panel
 */

import { useMutation, useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { useAgentHealth } from "@/lib/use-agent";
import { useTRPC } from "@/utils/trpc";
import { normalizeDatabaseName } from "./constants";

export function useDatabases() {
	const [dialogOpen, setDialogOpen] = useState(false);
	const [dbName, setDbName] = useState("");
	const [seedSnapshot, setSeedSnapshot] = useState("empty");
	const [runMigrations, setRunMigrations] = useState(true);
	const [provisioningRunId, setProvisioningRunId] = useState<number | null>(
		null,
	);

	const { isPaired } = useAgentHealth();
	const trpc = useTRPC();

	// Query for available snapshots
	const snapshotsQuery = useQuery(trpc.github.listSnapshots.queryOptions());

	// Mutation to provision database
	const provisionMutation = useMutation(
		trpc.github.provisionDatabase.mutationOptions({
			onSuccess: (data) => {
				if (data.runId) {
					setProvisioningRunId(data.runId);
				}
			},
		}),
	);

	// Query to poll workflow status
	const workflowStatusQuery = useQuery({
		...trpc.github.getWorkflowRun.queryOptions({ runId: provisioningRunId! }),
		enabled: provisioningRunId !== null,
		refetchInterval: (query) => {
			const data = query.state.data;
			if (data?.status === "completed") {
				return false;
			}
			return 3000; // Poll every 3 seconds
		},
	});

	const handleProvision = async () => {
		if (!dbName.trim()) return;

		provisionMutation.mutate({
			databaseName: normalizeDatabaseName(dbName),
			seedSnapshot: seedSnapshot === "empty" ? undefined : seedSnapshot,
			runMigrations,
		});
	};

	const handleDialogClose = () => {
		setDialogOpen(false);
		setDbName("");
		setSeedSnapshot("empty");
		setRunMigrations(true);
		setProvisioningRunId(null);
		provisionMutation.reset();
	};

	const handleRetry = () => {
		setProvisioningRunId(null);
		provisionMutation.reset();
	};

	const isProvisioning =
		provisionMutation.isPending ||
		(provisioningRunId !== null &&
			workflowStatusQuery.data?.status !== "completed");

	const provisioningComplete =
		provisioningRunId !== null &&
		workflowStatusQuery.data?.status === "completed";

	const provisioningSuccess =
		provisioningComplete && workflowStatusQuery.data?.conclusion === "success";

	return {
		// Dialog state
		dialogOpen,
		setDialogOpen,
		dbName,
		setDbName,
		seedSnapshot,
		setSeedSnapshot,
		runMigrations,
		setRunMigrations,

		// Agent status
		isPaired,

		// Snapshots
		snapshots: snapshotsQuery.data?.snapshots ?? [],
		snapshotsLoading: snapshotsQuery.isLoading,

		// Provisioning status
		isProvisioning,
		provisioningComplete,
		provisioningSuccess,
		provisioningError: provisionMutation.error?.message ?? null,
		workflowRunUrl: provisionMutation.data?.runUrl ?? null,
		workflowStatus: workflowStatusQuery.data?.status ?? null,

		// Actions
		handleProvision,
		handleDialogClose,
		handleRetry,
	};
}
