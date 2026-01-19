/**
 * Reusable components for the Databases Panel
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Checkbox } from "@ui/checkbox";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@ui/dialog";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "@ui/dropdown-menu";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Progress } from "@ui/progress";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
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
import type {
	DatabaseCardProps,
	CreateDatabaseDialogProps,
	ProvisioningStatusProps,
} from "./types";

// =============================================================================
// Database Card Component
// =============================================================================

export function DatabaseCard({ database }: DatabaseCardProps) {
	return (
		<Card>
			<CardHeader className="pb-3">
				<div className="flex items-start justify-between">
					<div className="flex items-center gap-3">
						<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
							<Database className="h-5 w-5 text-accent" />
						</div>
						<div>
							<CardTitle className="font-medium text-base">
								{database.name}
							</CardTitle>
							<p className="text-muted-foreground text-sm">
								{database.type} {database.version}
							</p>
						</div>
					</div>
					<div className="flex items-center gap-2">
						<Badge
							className={
								database.status === "online" ? "border-accent text-accent" : ""
							}
							variant="outline"
						>
							{database.status}
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
							{database.host}
						</code>
						<Button className="h-6 w-6 shrink-0" size="icon" variant="ghost">
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
							{database.storage.used} GB / {database.storage.total} GB
						</span>
					</div>
					<Progress
						className="h-1.5"
						value={(database.storage.used / database.storage.total) * 100}
					/>
				</div>

				<div className="grid grid-cols-2 gap-4 text-sm">
					<div className="flex items-center gap-2 text-muted-foreground">
						<Clock className="h-4 w-4" />
						<span>Backup: {database.lastBackup}</span>
					</div>
					<div className="flex items-center gap-2 text-muted-foreground">
						<Shield className="h-4 w-4" />
						<span>Connections: {database.connections}</span>
					</div>
				</div>
			</CardContent>
		</Card>
	);
}

// =============================================================================
// Provisioning Status Component
// =============================================================================

export function ProvisioningStatus({
	isProvisioning,
	provisioningComplete,
	provisioningSuccess,
	dbName,
	workflowRunUrl,
	onClose,
	onRetry,
	workflowStatus,
}: ProvisioningStatusProps) {
	if (isProvisioning) {
		return (
			<div className="rounded-lg border border-accent/30 bg-accent/5 p-4">
				<div className="flex items-center gap-3">
					<Loader2 className="h-5 w-5 animate-spin text-accent" />
					<div>
						<p className="font-medium text-foreground text-sm">
							Provisioning database...
						</p>
						<p className="text-muted-foreground text-xs">
							{workflowStatus || "Starting workflow"}
						</p>
					</div>
				</div>
				{workflowRunUrl && (
					<a
						className="mt-2 flex items-center gap-1 text-accent text-xs hover:underline"
						href={workflowRunUrl}
						rel="noopener noreferrer"
						target="_blank"
					>
						View in GitHub Actions
						<ExternalLink className="h-3 w-3" />
					</a>
				)}
			</div>
		);
	}

	if (provisioningComplete) {
		if (provisioningSuccess) {
			return (
				<div className="space-y-4 py-6 text-center">
					<div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-accent/10">
						<CheckCircle2 className="h-6 w-6 text-accent" />
					</div>
					<div>
						<p className="font-medium text-foreground">Database Created!</p>
						<p className="text-muted-foreground text-sm">
							Your database <code>{dbName}</code> is ready to use.
						</p>
					</div>
					{workflowRunUrl && (
						<a
							className="flex items-center justify-center gap-1 text-accent text-sm hover:underline"
							href={workflowRunUrl}
							rel="noopener noreferrer"
							target="_blank"
						>
							View workflow details
							<ExternalLink className="h-3 w-3" />
						</a>
					)}
					<Button className="mt-4" onClick={onClose} variant="outline">
						Close
					</Button>
				</div>
			);
		}

		return (
			<div className="space-y-4 py-6 text-center">
				<div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-destructive/10">
					<AlertCircle className="h-6 w-6 text-destructive" />
				</div>
				<div>
					<p className="font-medium text-foreground">Provisioning Failed</p>
					<p className="text-muted-foreground text-sm">
						Check the workflow logs for details.
					</p>
				</div>
				{workflowRunUrl && (
					<a
						className="flex items-center justify-center gap-1 text-accent text-sm hover:underline"
						href={workflowRunUrl}
						rel="noopener noreferrer"
						target="_blank"
					>
						View workflow logs
						<ExternalLink className="h-3 w-3" />
					</a>
				)}
				<div className="flex justify-center gap-2">
					<Button onClick={onClose} variant="outline">
						Close
					</Button>
					<Button onClick={onRetry}>
						<RefreshCw className="mr-2 h-4 w-4" />
						Try Again
					</Button>
				</div>
			</div>
		);
	}

	return null;
}

// =============================================================================
// Create Database Dialog
// =============================================================================

export function CreateDatabaseDialog({
	open,
	onOpenChange,
	dbName,
	onDbNameChange,
	seedSnapshot,
	onSeedSnapshotChange,
	runMigrations,
	onRunMigrationsChange,
	onProvision,
	onClose,
	isProvisioning,
	provisioningComplete,
	provisioningSuccess,
	provisioningError,
	workflowRunUrl,
	workflowStatus,
	isPaired,
	snapshots,
}: CreateDatabaseDialogProps) {
	return (
		<Dialog
			onOpenChange={(open) => !open && onClose()}
			open={open}
		>
			<DialogTrigger asChild>
				<Button
					className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"
					onClick={() => onOpenChange(true)}
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
									onChange={(e) => onDbNameChange(e.target.value)}
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
									onValueChange={onSeedSnapshotChange}
									value={seedSnapshot}
								>
									<SelectTrigger>
										<SelectValue placeholder="Start with empty database" />
									</SelectTrigger>
									<SelectContent>
										<SelectItem value="empty">Empty database</SelectItem>
										{snapshots.map((snapshot) => (
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
										onRunMigrationsChange(checked === true)
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

							{provisioningError && (
								<div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3">
									<p className="text-destructive text-sm">
										{provisioningError}
									</p>
								</div>
							)}

							<ProvisioningStatus
								isProvisioning={isProvisioning}
								provisioningComplete={false}
								provisioningSuccess={false}
								dbName={dbName}
								workflowRunUrl={workflowRunUrl}
								onClose={onClose}
								onRetry={() => {}}
								workflowStatus={workflowStatus}
							/>
						</div>

						<DialogFooter>
							<Button
								disabled={isProvisioning}
								onClick={onClose}
								variant="outline"
							>
								Cancel
							</Button>
							<Button
								className="bg-accent text-accent-foreground hover:bg-accent/90"
								disabled={!dbName.trim() || isProvisioning}
								onClick={onProvision}
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
					<ProvisioningStatus
						isProvisioning={isProvisioning}
						provisioningComplete={provisioningComplete}
						provisioningSuccess={provisioningSuccess}
						dbName={dbName}
						workflowRunUrl={workflowRunUrl}
						onClose={onClose}
						onRetry={() => {}}
						workflowStatus={workflowStatus}
					/>
				)}
			</DialogContent>
		</Dialog>
	);
}
