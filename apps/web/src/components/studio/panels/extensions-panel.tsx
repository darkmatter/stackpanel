/**
 * Extensions Panel
 *
 * Displays extension panels from the Nix configuration.
 * Uses nix eval to get live config with extensions and their panels.
 */

import { Loader2, Puzzle } from "lucide-react";
import {
	type AppData,
	type Extension,
	renderExtensionPanels,
} from "@/lib/extension-panels";
import { useNixConfig } from "@/lib/use-nix-config";

const _data = {
	debug: true,
	enable: true,
	extensions: {
		caddy: {
			apps: {
				docs: {
					config: { domain: "docs", tls: "false", url: "" },
					enabled: true,
				},
				web: {
					config: { domain: "stackpanel", tls: "true", url: "" },
					enabled: true,
				},
			},
			enabled: true,
			name: "Caddy",
			panels: [
				{
					description: null,
					fields: [
						{
							name: "metrics",
							options: [],
							type: "FIELD_TYPE_STRING",
							value:
								'[{"label":"Project","status":"ok","value":"stackpanel"},{"label":"Port","status":"ok","value":"6493"},{"label":"TLS","status":"warning","value":"Disabled"},{"label":"Virtual Hosts","status":"ok","value":"2"}]',
						},
					],
					id: "caddy-status",
					order: 1,
					title: "Caddy Reverse Proxy",
					type: "PANEL_TYPE_STATUS",
				},
				{
					description: null,
					fields: [
						{
							name: "columns",
							options: [],
							type: "FIELD_TYPE_COLUMNS",
							value: '["name","port"]',
						},
					],
					id: "caddy-apps",
					order: 2,
					title: "Virtual Hosts",
					type: "PANEL_TYPE_APPS_GRID",
				},
			],
			priority: 20,
			tags: ["networking", "proxy"],
		},
		example: {
			apps: {
				docs: { config: { hasUrl: "no", path: "" }, enabled: true },
				server: { config: { hasUrl: "no", path: "" }, enabled: true },
				"stackpanel-go": {
					config: { hasUrl: "no", path: "apps/stackpanel-go" },
					enabled: true,
				},
				web: { config: { hasUrl: "no", path: "" }, enabled: true },
			},
			enabled: true,
			name: "Example Extension",
			panels: [
				{
					description: "Shows basic system and Nix information",
					fields: [
						{
							name: "metrics",
							options: [],
							type: "FIELD_TYPE_STRING",
							value:
								'[{"label":"Nix Version","status":"ok","value":"2.33.0"},{"label":"System","status":"ok","value":"aarch64-darwin"},{"label":"Custom Message","status":"ok","value":"Welcome to Stackpanel!"},{"label":"Extension Status","status":"ok","value":"Active"}]',
						},
					],
					id: "example-status",
					order: 1,
					title: "System Information",
					type: "PANEL_TYPE_STATUS",
				},
				{
					description: "Shows all apps in the stackpanel configuration",
					fields: [
						{
							name: "columns",
							options: [],
							type: "FIELD_TYPE_COLUMNS",
							value: '["name","path","port","config"]',
						},
					],
					id: "example-apps",
					order: 2,
					title: "All Applications",
					type: "PANEL_TYPE_APPS_GRID",
				},
			],
			priority: 999,
			tags: ["example", "demo"],
		},
		go: {
			apps: {
				"stackpanel-go": {
					config: {
						binaryName: "stackpanel",
						mainPackage: ".",
						path: "apps/stackpanel-go",
						version: "0.1.0",
					},
					enabled: true,
				},
			},
			enabled: true,
			name: "Go",
			panels: [
				{
					description: null,
					fields: [
						{
							name: "columns",
							options: [],
							type: "FIELD_TYPE_COLUMNS",
							value: '["name","path","version","port"]',
						},
					],
					id: "go-apps-grid",
					order: 1,
					title: "Go Applications",
					type: "PANEL_TYPE_APPS_GRID",
				},
				{
					description: null,
					fields: [
						{
							name: "metrics",
							options: [],
							type: "FIELD_TYPE_STRING",
							value:
								'[{"label":"Go Version","status":"ok","value":"1.25.5"},{"label":"Apps","status":"ok","value":"1"}]',
						},
					],
					id: "go-status",
					order: 2,
					title: "Go Environment",
					type: "PANEL_TYPE_STATUS",
				},
			],
			priority: 10,
			tags: ["language", "backend"],
		},
	},
	github: "darkmatter/stackpanel",
	motd: {
		commands: [
			{ description: "Export AWS credentials to env", name: "aws-creds-env" },
			{ description: "Verify AWS cert-auth status", name: "check-aws-cert" },
			{
				description: "Request/renew device certificate",
				name: "ensure-device-cert",
			},
			{ description: "Verify certificate status", name: "check-device-cert" },
			{
				description: "Export AWS credentials to environment",
				name: "aws-creds-env",
			},
		],
		enable: true,
		features: [
			"Starship prompt theme",
			"AWS Roles Anywhere (darkmatter-dev)",
			"Step CA certificates (https://ca.internal:443)",
		],
		hints: [
			"Open .stackpanel/gen/vscode/stackpanel.code-workspace in VS Code for integrated terminal",
			"Open .stackpanel/gen/ide/vscode/stackpanel.code-workspace in VS Code for integrated terminal",
			"Run './test' to test both devenv and native shells",
			"Run './test devenv' or './test native' to test individual shells",
			"Run 'nix flake check --impure' to run all checks including smoke tests",
		],
	},
	name: "stackpanel",
	ports: {
		"base-port": 6400,
		enable: true,
		"project-name": "stackpanel",
		service: {
			MINIO: { displayName: "Minio", key: "MINIO", name: "Minio", port: 6498 },
			MINIO_CONSOLE: {
				displayName: "Minio Console",
				key: "MINIO_CONSOLE",
				name: "Minio Console",
				port: 6436,
			},
			POSTGRES: {
				displayName: "PostgreSQL",
				key: "POSTGRES",
				name: "PostgreSQL",
				port: 6404,
			},
			REDIS: { displayName: "Redis", key: "REDIS", name: "Redis", port: 6494 },
		},
		services: {
			MINIO: { name: "Minio" },
			MINIO_CONSOLE: { name: "Minio Console" },
			POSTGRES: { name: "PostgreSQL" },
			REDIS: { name: "Redis" },
		},
	},
};

export function ExtensionsPanel() {
	const { data: _config, isLoading, isError, error, refetch } = useNixConfig();
	const config = _data; // TODO: Remove when not mocking

	// if (isLoading) {
	//   return (
	//     <div className="flex min-h-[400px] items-center justify-center">
	//       <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
	//     </div>
	//   );
	// }

	// if (isError) {
	//   return (
	//     <div className="flex min-h-[400px] flex-col items-center justify-center gap-4">
	//       <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
	//         <p className="text-sm text-destructive">
	//           Failed to load extensions: {error?.message || "Unknown error"}
	//         </p>
	//       </div>
	//       <button
	//         type="button"
	//         onClick={() => refetch()}
	//         className="text-sm text-primary underline-offset-4 hover:underline"
	//       >
	//         Try again
	//       </button>
	//     </div>
	//   );
	// }

	// Extract extensions from config
	const extensions = (config as Record<string, unknown>)?.extensions as
		| Record<string, Extension>
		| undefined;
	const apps = (config as Record<string, unknown>)?.apps as
		| Record<string, AppData>
		| undefined;

	if (!extensions || Object.keys(extensions).length === 0) {
		return <EmptyState />;
	}

	// Sort extensions by priority
	const sortedExtensions = Object.entries(extensions).sort(
		([, a], [, b]) => (a.priority ?? 100) - (b.priority ?? 100),
	);

	return (
		<div className="space-y-8">
			<div className="space-y-2">
				<h1 className="flex items-center gap-2 text-2xl font-bold">
					<Puzzle className="h-6 w-6" />
					Extensions
				</h1>
				<p className="text-muted-foreground">
					Extension panels from your Nix configuration
				</p>
			</div>

			<div className="space-y-10">
				{sortedExtensions.map(([key, extension]) => (
					<ExtensionSection
						key={key}
						extensionKey={key}
						extension={extension}
						allApps={apps ?? {}}
					/>
				))}
			</div>
		</div>
	);
}

/**
 * Section for a single extension with its panels
 */
function ExtensionSection({
	extensionKey,
	extension,
	allApps,
}: {
	extensionKey: string;
	extension: Extension;
	allApps: Record<string, AppData>;
}) {
	const panels = renderExtensionPanels(extension, allApps);

	if (panels.length === 0) {
		return null;
	}

	return (
		<section className="space-y-4">
			<div className="flex items-center gap-3">
				<h2 className="text-xl font-semibold">{extension.name}</h2>
				{extension.tags && extension.tags.length > 0 && (
					<div className="flex gap-1">
						{extension.tags.map((tag) => (
							<span
								key={tag}
								className="rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground"
							>
								{tag}
							</span>
						))}
					</div>
				)}
			</div>
			<div className="grid gap-4 md:grid-cols-2">{panels}</div>
		</section>
	);
}

/**
 * Empty state when no extensions are configured
 */
function EmptyState() {
	return (
		<div className="flex min-h-[400px] flex-col items-center justify-center gap-4">
			<Puzzle className="h-16 w-16 text-muted-foreground/50" />
			<div className="text-center">
				<h2 className="text-xl font-semibold">No Extensions</h2>
				<p className="mt-1 text-sm text-muted-foreground">
					Extensions with UI panels will appear here.
				</p>
				<p className="mt-2 text-xs text-muted-foreground">
					Enable extensions in your Nix modules by setting{" "}
					<code className="rounded bg-muted px-1 py-0.5">
						stackpanel.extensions.&lt;name&gt;
					</code>
				</p>
			</div>
		</div>
	);
}
