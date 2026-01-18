"use client";

import { Button } from "@ui/button";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@ui/card";
import { Textarea } from "@ui/textarea";
import {
	AlertCircle,
	Check,
	FileCode2,
	Info,
	Loader2,
	RefreshCw,
	Save,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { useAgent } from "@/lib/use-agent";
import { PanelHeader } from "./shared/panel-header";

const LOCAL_CONFIG_PATH = ".stackpanel/config.local.nix";

const DEFAULT_TEMPLATE = `# ==============================================================================
# config.local.nix
#
# Per-user local overrides (gitignored)
#
# This file is merged on top of config.nix, allowing you to override
# any configuration for your local development environment without
# affecting the shared project configuration.
#
# Common use cases:
#   - Add packages you personally prefer
#   - Override debug settings
#   - Customize theme or IDE settings
#   - Test configuration changes before committing
#
# Priority (lowest to highest):
#   1. Data tables (.stackpanel/data/*.nix)
#   2. Main config (.stackpanel/config.nix)
#   3. Local overrides (.stackpanel/config.local.nix) ← You are here
# ==============================================================================
{ pkgs }:
{
  # Example: Add personal development packages
  # packages = with pkgs; [
  #   ripgrep
  #   htop
  # ];

  # Example: Override debug mode
  # debug = true;

  # Example: Disable theme for minimal shell
  # theme.enable = false;
}
`;

export function LocalConfigPanel() {
	const { isConnected, readFile, writeFile } = useAgent();
	const [content, setContent] = useState<string>("");
	const [originalContent, setOriginalContent] = useState<string>("");
	const [exists, setExists] = useState<boolean>(false);
	const [loading, setLoading] = useState<boolean>(true);
	const [saving, setSaving] = useState<boolean>(false);
	const [error, setError] = useState<string | null>(null);

	const hasChanges = content !== originalContent;

	const loadFile = useCallback(async () => {
		if (!isConnected) return;

		setLoading(true);
		setError(null);

		try {
			const result = await readFile(LOCAL_CONFIG_PATH);
			if (result.exists) {
				setContent(result.content);
				setOriginalContent(result.content);
				setExists(true);
			} else {
				setContent("");
				setOriginalContent("");
				setExists(false);
			}
		} catch (err) {
			setError(err instanceof Error ? err.message : "Failed to load file");
		} finally {
			setLoading(false);
		}
	}, [isConnected, readFile]);

	useEffect(() => {
		if (isConnected) {
			loadFile();
		}
	}, [isConnected, loadFile]);

	const handleSave = async () => {
		if (!isConnected) return;

		setSaving(true);
		setError(null);

		try {
			await writeFile(LOCAL_CONFIG_PATH, content);
			setOriginalContent(content);
			setExists(true);
			toast.success("Local config saved", {
				description:
					"Run 'direnv reload' or re-enter the devshell to apply changes",
			});
		} catch (err) {
			const message =
				err instanceof Error ? err.message : "Failed to save file";
			setError(message);
			toast.error("Failed to save", { description: message });
		} finally {
			setSaving(false);
		}
	};

	const handleCreateFromTemplate = async () => {
		if (!isConnected) return;

		setSaving(true);
		setError(null);

		try {
			await writeFile(LOCAL_CONFIG_PATH, DEFAULT_TEMPLATE);
			setContent(DEFAULT_TEMPLATE);
			setOriginalContent(DEFAULT_TEMPLATE);
			setExists(true);
			toast.success("Local config created", {
				description: "Edit the file to add your personal overrides",
			});
		} catch (err) {
			const message =
				err instanceof Error ? err.message : "Failed to create file";
			setError(message);
			toast.error("Failed to create", { description: message });
		} finally {
			setSaving(false);
		}
	};

	const handleDelete = async () => {
		if (!isConnected) return;

		setSaving(true);
		setError(null);

		try {
			// Write empty content to effectively "delete" (we can't actually delete via API)
			await writeFile(LOCAL_CONFIG_PATH, "");
			setContent("");
			setOriginalContent("");
			setExists(false);
			toast.success("Local config cleared");
		} catch (err) {
			const message =
				err instanceof Error ? err.message : "Failed to clear file";
			setError(message);
			toast.error("Failed to clear", { description: message });
		} finally {
			setSaving(false);
		}
	};

	if (!isConnected) {
		return (
			<div className="space-y-6">
				<PanelHeader
					title="Local Config"
					description="Per-user configuration overrides"
					guideKey="configuration"
				/>
				<Card>
					<CardContent className="py-12 text-center">
						<AlertCircle className="mx-auto h-12 w-12 text-muted-foreground/50 mb-4" />
						<p className="text-muted-foreground">
							Connect to an agent to edit local config
						</p>
					</CardContent>
				</Card>
			</div>
		);
	}

	if (loading) {
		return (
			<div className="space-y-6">
				<PanelHeader
					title="Local Config"
					description="Per-user configuration overrides"
					guideKey="configuration"
				/>
				<Card>
					<CardContent className="py-12 text-center">
						<Loader2 className="mx-auto h-8 w-8 animate-spin text-muted-foreground" />
						<p className="text-muted-foreground mt-2">Loading...</p>
					</CardContent>
				</Card>
			</div>
		);
	}

	return (
		<div className="space-y-6">
			<PanelHeader
				title="Local Config"
				description="Per-user configuration overrides (gitignored)"
				guideKey="configuration"
			/>

			{/* Info banner */}
			<div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4">
				<div className="flex gap-3">
					<Info className="h-5 w-5 text-blue-500 shrink-0 mt-0.5" />
					<div className="text-sm text-blue-700 dark:text-blue-300 space-y-1">
						<p className="font-medium">About Local Config</p>
						<p className="text-blue-600 dark:text-blue-400">
							This file is gitignored and allows you to override any setting
							from{" "}
							<code className="px-1 py-0.5 rounded bg-blue-500/10 text-xs">
								config.nix
							</code>{" "}
							for your local environment only. Changes are applied on next
							devshell entry.
						</p>
					</div>
				</div>
			</div>

			{error && (
				<div className="rounded-lg border border-destructive/20 bg-destructive/5 p-4">
					<div className="flex gap-3">
						<AlertCircle className="h-5 w-5 text-destructive shrink-0" />
						<p className="text-sm text-destructive">{error}</p>
					</div>
				</div>
			)}

			<Card>
				<CardHeader className="flex flex-row items-center justify-between space-y-0 pb-4">
					<div className="space-y-1">
						<CardTitle className="flex items-center gap-2 text-lg">
							<FileCode2 className="h-5 w-5 text-accent" />
							{LOCAL_CONFIG_PATH}
						</CardTitle>
						<CardDescription>
							{exists
								? "Edit your local overrides below"
								: "No local config file exists yet"}
						</CardDescription>
					</div>
					<div className="flex items-center gap-2">
						<Button
							variant="ghost"
							size="sm"
							onClick={loadFile}
							disabled={loading || saving}
						>
							<RefreshCw
								className={`h-4 w-4 ${loading ? "animate-spin" : ""}`}
							/>
						</Button>
					</div>
				</CardHeader>

				<CardContent className="space-y-4">
					{exists ? (
						<>
							<Textarea
								className="font-mono text-sm min-h-[400px] resize-y"
								value={content}
								onChange={(e) => setContent(e.target.value)}
								placeholder="Enter your Nix configuration..."
								spellCheck={false}
							/>
							<div className="flex items-center justify-between">
								<div className="flex items-center gap-2">
									{hasChanges && (
										<span className="text-xs text-muted-foreground flex items-center gap-1">
											<AlertCircle className="h-3 w-3" />
											Unsaved changes
										</span>
									)}
									{!hasChanges && originalContent && (
										<span className="text-xs text-emerald-600 dark:text-emerald-400 flex items-center gap-1">
											<Check className="h-3 w-3" />
											Saved
										</span>
									)}
								</div>
								<div className="flex items-center gap-2">
									<Button
										variant="outline"
										size="sm"
										onClick={handleDelete}
										disabled={saving || !exists}
									>
										Clear File
									</Button>
									<Button
										size="sm"
										onClick={handleSave}
										disabled={saving || !hasChanges}
									>
										{saving ? (
											<>
												<Loader2 className="mr-2 h-4 w-4 animate-spin" />
												Saving...
											</>
										) : (
											<>
												<Save className="mr-2 h-4 w-4" />
												Save
											</>
										)}
									</Button>
								</div>
							</div>
						</>
					) : (
						<div className="py-8 text-center space-y-4">
							<FileCode2 className="mx-auto h-12 w-12 text-muted-foreground/30" />
							<div className="space-y-1">
								<p className="text-muted-foreground">
									No local config file found
								</p>
								<p className="text-xs text-muted-foreground/70">
									Create one to override settings for your local environment
								</p>
							</div>
							<Button onClick={handleCreateFromTemplate} disabled={saving}>
								{saving ? (
									<Loader2 className="mr-2 h-4 w-4 animate-spin" />
								) : (
									<FileCode2 className="mr-2 h-4 w-4" />
								)}
								Create from Template
							</Button>
						</div>
					)}
				</CardContent>
			</Card>
		</div>
	);
}
