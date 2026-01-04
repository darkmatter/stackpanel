"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import {
	AlertCircle,
	CheckCircle2,
	Clock,
	Copy,
	Database,
	ExternalLink,
	HardDrive,
	Loader2,
	MoreVertical,
	Plus,
	RefreshCw,
	Shield,
} from "lucide-react";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@/components/ui/dialog";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Progress } from "@/components/ui/progress";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@/components/ui/select";
import { useAgentHealth } from "@/lib/use-agent";
import { useTRPC } from "@/utils/trpc";

const databases = [
	{
		name: "main-postgres",
		type: "PostgreSQL",
		version: "15.2",
		status: "online",
		connections: "23/100",
		storage: { used: 12.4, total: 50 },
		host: "main-postgres.internal.acme.com",
		lastBackup: "2 hours ago",
		ssl: true,
	},
	{
		name: "auth-postgres",
		type: "PostgreSQL",
		version: "15.2",
		status: "online",
		connections: "8/50",
		storage: { used: 2.1, total: 20 },
		host: "auth-postgres.internal.acme.com",
		lastBackup: "1 hour ago",
		ssl: true,
	},
	{
		name: "cache-redis",
		type: "Redis",
		version: "7.0",
		status: "online",
		connections: "156/1000",
		storage: { used: 0.8, total: 4 },
		host: "cache-redis.internal.acme.com",
		lastBackup: "N/A",
		ssl: true,
	},
	{
		name: "analytics-clickhouse",
		type: "ClickHouse",
		version: "23.3",
		status: "online",
		connections: "12/50",
		storage: { used: 45.2, total: 200 },
		host: "analytics-clickhouse.internal.acme.com",
		lastBackup: "6 hours ago",
		ssl: true,
	},
];

export function DatabasesPanel() {
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
			databaseName: dbName.toLowerCase().replace(/[^a-z0-9_]/g, "_"),
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

	const isProvisioning =
		provisionMutation.isPending ||
		(provisioningRunId !== null &&
			workflowStatusQuery.data?.status !== "completed");

	const provisioningComplete =
		provisioningRunId !== null &&
		workflowStatusQuery.data?.status === "completed";

	const provisioningSuccess =
		provisioningComplete && workflowStatusQuery.data?.conclusion === "success";

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h2 className="font-semibold text-foreground text-xl">Databases</h2>
					<p className="text-muted-foreground text-sm">
						Manage your database instances and connections
					</p>
				</div>
				<Dialog
					onOpenChange={(open) => !open && handleDialogClose()}
					open={dialogOpen}
				>
					<DialogTrigger asChild>
						<Button
							className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"
							onClick={() => setDialogOpen(true)}
						>
							<Plus className="h-4 w-4" />
							Create Database
						</Button>
					</DialogTrigger>
					<DialogContent className="sm:max-w-md">
						<DialogHeader>
							<DialogTitle>Create New Database</DialogTitle>
							<DialogDescription>
								Provision a new PostgreSQL database on the internal server.
							</DialogDescription>
						</DialogHeader>

						{!provisioningComplete ? (
							<>
								<div className="grid gap-4 py-4">
									<div className="grid gap-2">
										<Label htmlFor="db-name">Database Name</Label>
										<Input
											disabled={isProvisioning}
											id="db-name"
											onChange={(e) => setDbName(e.target.value)}
											placeholder="my_database"
											value={dbName}
										/>
										<p className="text-muted-foreground text-xs">
											Lowercase letters, numbers, and underscores only
										</p>
									</div>

									<div className="grid gap-2">
										<Label>Seed from Snapshot (optional)</Label>
										<Select
											disabled={isProvisioning}
											onValueChange={setSeedSnapshot}
											value={seedSnapshot}
										>
											<SelectTrigger>
												<SelectValue placeholder="Start with empty database" />
											</SelectTrigger>
											<SelectContent>
												<SelectItem value="empty">Empty database</SelectItem>
												{snapshotsQuery.data?.snapshots.map((snapshot) => (
													<SelectItem key={snapshot.key} value={snapshot.key}>
														{snapshot.description || snapshot.key}
														{snapshot.isDefault && " (default)"}
													</SelectItem>
												))}
											</SelectContent>
										</Select>
									</div>

									<div className="flex items-center gap-2">
										<Checkbox
											checked={runMigrations}
											disabled={isProvisioning}
											id="run-migrations"
											onCheckedChange={(checked) =>
												setRunMigrations(checked === true)
											}
										/>
										<Label className="cursor-pointer" htmlFor="run-migrations">
											Run migrations after creation
										</Label>
									</div>

									{!isPaired && (
										<div className="rounded-lg border border-yellow-500/30 bg-yellow-500/5 p-3">
											<p className="text-muted-foreground text-sm">
												<AlertCircle className="mr-2 inline h-4 w-4 text-yellow-500" />
												Connect to the local agent to save credentials to your
												project.
											</p>
										</div>
									)}

									{provisionMutation.isError && (
										<div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3">
											<p className="text-destructive text-sm">
												{provisionMutation.error?.message ||
													"Failed to start provisioning"}
											</p>
										</div>
									)}

									{isProvisioning && (
										<div className="rounded-lg border border-accent/30 bg-accent/5 p-4">
											<div className="flex items-center gap-3">
												<Loader2 className="h-5 w-5 animate-spin text-accent" />
												<div>
													<p className="font-medium text-foreground text-sm">
														Provisioning database...
													</p>
													<p className="text-muted-foreground text-xs">
														{workflowStatusQuery.data?.status ||
															"Starting workflow"}
													</p>
												</div>
											</div>
											{provisionMutation.data?.runUrl && (
												<a
													className="mt-2 flex items-center gap-1 text-accent text-xs hover:underline"
													href={provisionMutation.data.runUrl}
													rel="noopener noreferrer"
													target="_blank"
												>
													View in GitHub Actions
													<ExternalLink className="h-3 w-3" />
												</a>
											)}
										</div>
									)}
								</div>

								<DialogFooter>
									<Button
										disabled={isProvisioning}
										onClick={handleDialogClose}
										variant="outline"
									>
										Cancel
									</Button>
									<Button
										className="bg-accent text-accent-foreground hover:bg-accent/90"
										disabled={!dbName.trim() || isProvisioning}
										onClick={handleProvision}
									>
										{isProvisioning ? (
											<>
												<Loader2 className="mr-2 h-4 w-4 animate-spin" />
												Provisioning...
											</>
										) : (
											"Create Database"
										)}
									</Button>
								</DialogFooter>
							</>
						) : (
							<div className="py-6">
								{provisioningSuccess ? (
									<div className="space-y-4 text-center">
										<div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-accent/10">
											<CheckCircle2 className="h-6 w-6 text-accent" />
										</div>
										<div>
											<p className="font-medium text-foreground">
												Database Created!
											</p>
											<p className="text-muted-foreground text-sm">
												Your database <code>{dbName}</code> is ready to use.
											</p>
										</div>
										{provisionMutation.data?.runUrl && (
											<a
												className="flex items-center justify-center gap-1 text-accent text-sm hover:underline"
												href={provisionMutation.data.runUrl}
												rel="noopener noreferrer"
												target="_blank"
											>
												View workflow details
												<ExternalLink className="h-3 w-3" />
											</a>
										)}
										<Button
											className="mt-4"
											onClick={handleDialogClose}
											variant="outline"
										>
											Close
										</Button>
									</div>
								) : (
									<div className="space-y-4 text-center">
										<div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-destructive/10">
											<AlertCircle className="h-6 w-6 text-destructive" />
										</div>
										<div>
											<p className="font-medium text-foreground">
												Provisioning Failed
											</p>
											<p className="text-muted-foreground text-sm">
												Check the workflow logs for details.
											</p>
										</div>
										{provisionMutation.data?.runUrl && (
											<a
												className="flex items-center justify-center gap-1 text-accent text-sm hover:underline"
												href={provisionMutation.data.runUrl}
												rel="noopener noreferrer"
												target="_blank"
											>
												View workflow logs
												<ExternalLink className="h-3 w-3" />
											</a>
										)}
										<div className="flex justify-center gap-2">
											<Button onClick={handleDialogClose} variant="outline">
												Close
											</Button>
											<Button
												onClick={() => {
													setProvisioningRunId(null);
													provisionMutation.reset();
												}}
											>
												<RefreshCw className="mr-2 h-4 w-4" />
												Try Again
											</Button>
										</div>
									</div>
								)}
							</div>
						)}
					</DialogContent>
				</Dialog>
			</div>

			<div className="grid gap-4 md:grid-cols-2">
				{databases.map((db) => (
					<Card key={db.name}>
						<CardHeader className="pb-3">
							<div className="flex items-start justify-between">
								<div className="flex items-center gap-3">
									<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
										<Database className="h-5 w-5 text-accent" />
									</div>
									<div>
										<CardTitle className="font-medium text-base">
											{db.name}
										</CardTitle>
										<p className="text-muted-foreground text-sm">
											{db.type} {db.version}
										</p>
									</div>
								</div>
								<div className="flex items-center gap-2">
									<Badge
										className={
											db.status === "online" ? "border-accent text-accent" : ""
										}
										variant="outline"
									>
										{db.status}
									</Badge>
									<DropdownMenu>
										<DropdownMenuTrigger asChild>
											<Button className="h-8 w-8" size="icon" variant="ghost">
												<MoreVertical className="h-4 w-4" />
											</Button>
										</DropdownMenuTrigger>
										<DropdownMenuContent align="end">
											<DropdownMenuItem>
												<ExternalLink className="mr-2 h-4 w-4" />
												Open Console
											</DropdownMenuItem>
											<DropdownMenuItem>View metrics</DropdownMenuItem>
											<DropdownMenuItem>Backup now</DropdownMenuItem>
											<DropdownMenuItem>Edit config</DropdownMenuItem>
											<DropdownMenuItem className="text-destructive">
												Delete
											</DropdownMenuItem>
										</DropdownMenuContent>
									</DropdownMenu>
								</div>
							</div>
						</CardHeader>
						<CardContent className="space-y-4">
							<div className="rounded-lg border border-border bg-secondary/30 p-3">
								<div className="flex items-center justify-between">
									<code className="flex-1 truncate text-muted-foreground text-xs">
										{db.host}
									</code>
									<Button
										className="h-6 w-6 shrink-0"
										size="icon"
										variant="ghost"
									>
										<Copy className="h-3 w-3" />
									</Button>
								</div>
							</div>

							<div className="space-y-2">
								<div className="flex items-center justify-between text-sm">
									<span className="flex items-center gap-2 text-muted-foreground">
										<HardDrive className="h-4 w-4" />
										Storage
									</span>
									<span className="text-foreground">
										{db.storage.used} GB / {db.storage.total} GB
									</span>
								</div>
								<Progress
									className="h-1.5"
									value={(db.storage.used / db.storage.total) * 100}
								/>
							</div>

							<div className="grid grid-cols-2 gap-4 text-sm">
								<div className="flex items-center gap-2 text-muted-foreground">
									<Clock className="h-4 w-4" />
									<span>Backup: {db.lastBackup}</span>
								</div>
								<div className="flex items-center gap-2 text-muted-foreground">
									<Shield className="h-4 w-4" />
									<span>Connections: {db.connections}</span>
								</div>
							</div>
						</CardContent>
					</Card>
				))}
			</div>
		</div>
	);
}
