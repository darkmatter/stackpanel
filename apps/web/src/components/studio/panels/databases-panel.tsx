"use client";

import { DatabaseCard, CreateDatabaseDialog, useDatabases, MOCK_DATABASES } from "./databases";

export function DatabasesPanel() {
	const {
		dialogOpen,
		setDialogOpen,
		dbName,
		setDbName,
		seedSnapshot,
		setSeedSnapshot,
		runMigrations,
		setRunMigrations,
		isPaired,
		snapshots,
		snapshotsLoading,
		isProvisioning,
		provisioningComplete,
		provisioningSuccess,
		provisioningError,
		workflowRunUrl,
		workflowStatus,
		handleProvision,
		handleDialogClose,
		handleRetry: _handleRetry,
	} = useDatabases();

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h2 className="font-semibold text-foreground text-xl">Databases</h2>
					<p className="text-muted-foreground text-sm">
						Manage your database instances and connections
					</p>
				</div>
				<CreateDatabaseDialog
					open={dialogOpen}
					onOpenChange={setDialogOpen}
					dbName={dbName}
					onDbNameChange={setDbName}
					seedSnapshot={seedSnapshot}
					onSeedSnapshotChange={setSeedSnapshot}
					runMigrations={runMigrations}
					onRunMigrationsChange={setRunMigrations}
					onProvision={handleProvision}
					onClose={handleDialogClose}
					isProvisioning={isProvisioning}
					provisioningComplete={provisioningComplete}
					provisioningSuccess={provisioningSuccess}
					provisioningError={provisioningError}
					workflowRunUrl={workflowRunUrl}
					workflowStatus={workflowStatus}
					isPaired={isPaired}
					snapshots={snapshots}
					snapshotsLoading={snapshotsLoading}
				/>
			</div>

			<div className="grid gap-4 md:grid-cols-2">
				{MOCK_DATABASES.map((db) => (
					<DatabaseCard key={db.name} database={db} />
				))}
			</div>
		</div>
	);
}
