/**
 * Apps Grid Panel Component
 *
 * Displays a grid of apps that have this extension enabled.
 * Shows app info like name, path, port, and extension-specific config.
 */

import { Badge } from "@ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import type { AppsGridProps } from "../types";

/**
 * Combined app data (base app + extension-specific config)
 */
interface CombinedAppData {
	name: string;
	port?: number;
	domain?: string | null;
	url?: string | null;
	tls?: boolean;
	path?: string;
	version?: string;
	[key: string]: unknown;
}

export function AppsGridPanel({
	extension,
	allApps,
	filter: _filter,
	columns = ["name", "path", "status"],
}: AppsGridProps) {
	// Filter apps that have this extension enabled
	const extensionApps: CombinedAppData[] = Object.entries(extension.apps)
		.filter(([_, data]) => data.enabled)
		.map(([appName, extData]) => ({
			name: appName,
			// Base app data (port, domain, url, tls)
			...(allApps[appName] || {}),
			// Extension-specific computed values
			...extData.config,
		}));

	if (extensionApps.length === 0) {
		return (
			<Card>
				<CardHeader>
					<CardTitle className="flex items-center gap-2">
						{extension.name} Apps
						<Badge variant="secondary">0</Badge>
					</CardTitle>
				</CardHeader>
				<CardContent>
					<p className="text-sm text-muted-foreground">
						No apps have this extension enabled.
					</p>
				</CardContent>
			</Card>
		);
	}

	return (
		<Card>
			<CardHeader>
				<CardTitle className="flex items-center gap-2">
					{extension.name} Apps
					<Badge variant="secondary">{extensionApps.length}</Badge>
				</CardTitle>
			</CardHeader>
			<CardContent>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
					{extensionApps.map((app) => (
						<AppCard key={app.name} app={app} columns={columns} />
					))}
				</div>
			</CardContent>
		</Card>
	);
}

/**
 * Individual app card within the grid
 */
function AppCard({
	app,
	columns,
}: {
	app: CombinedAppData;
	columns: string[];
}) {
	return (
		<div className="rounded-lg border p-4 transition-colors hover:bg-muted/50">
			<div className="flex items-start justify-between">
				<div className="space-y-1">
					<h4 className="font-medium leading-none">{app.name}</h4>
				{columns.includes("path") && app.path && (
					<p className="text-sm text-muted-foreground">{String(app.path)}</p>
				)}
			</div>
			<div className="flex items-center gap-2">
				{columns.includes("version") && app.version != null && (
					<Badge variant="outline">v{String(app.version)}</Badge>
				)}
					{columns.includes("port") && app.port && (
						<Badge variant="secondary">:{app.port}</Badge>
					)}
				</div>
			</div>

			{/* Additional info based on available data */}
			<div className="mt-3 flex flex-wrap gap-2">
				{app.url && (
					<a
						href={app.url}
						target="_blank"
						rel="noopener noreferrer"
						className="text-xs text-primary underline-offset-4 hover:underline"
					>
						{app.domain || app.url}
					</a>
				)}
				{app.tls && (
					<Badge variant="outline" className="text-xs">
						TLS
					</Badge>
				)}
			</div>

			{/* Show any extra config values */}
			{columns.includes("config") && (
				<div className="mt-2 flex flex-wrap gap-1">
					{Object.entries(app)
						.filter(
							([key]) =>
								![
									"name",
									"port",
									"domain",
									"url",
									"tls",
									"path",
									"version",
								].includes(key),
						)
						.slice(0, 3)
						.map(([key, value]) => (
							<Badge key={key} variant="outline" className="text-xs">
								{key}: {String(value)}
							</Badge>
						))}
				</div>
			)}
		</div>
	);
}
