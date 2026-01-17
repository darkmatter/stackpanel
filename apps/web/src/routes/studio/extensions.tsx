/**
 * Extensions Page
 *
 * Displays extension panels from the Nix configuration.
 * Uses nix eval to get live config with extensions and their panels.
 */

import { createFileRoute } from "@tanstack/react-router";
import { Loader2, Puzzle } from "lucide-react";
import {
	type AppData,
	type Extension,
	renderExtensionPanels,
} from "@/lib/extension-panels";
import { useNixConfig } from "@/lib/use-nix-config";

export const Route = createFileRoute("/studio/extensions")({
	component: ExtensionsPage,
});

function ExtensionsPage() {
	const { data: config, isLoading, isError, error, refetch } = useNixConfig();

	if (isLoading) {
		return (
			<div className="flex min-h-[400px] items-center justify-center">
				<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
			</div>
		);
	}

	if (isError) {
		return (
			<div className="flex min-h-[400px] flex-col items-center justify-center gap-4">
				<div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
					<p className="text-sm text-destructive">
						Failed to load extensions: {error?.message || "Unknown error"}
					</p>
				</div>
				<button
					type="button"
					onClick={() => refetch()}
					className="text-sm text-primary underline-offset-4 hover:underline"
				>
					Try again
				</button>
			</div>
		);
	}

	// Extract extensions from config
	// The config comes from nix eval, extensions are at config.extensions
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
		<div className="container mx-auto space-y-8 py-8">
			<div className="space-y-2">
				<h1 className="flex items-center gap-2 text-3xl font-bold">
					<Puzzle className="h-8 w-8" />
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
				<h2 className="text-2xl font-semibold">{extension.name}</h2>
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
