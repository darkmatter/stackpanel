/**
 * Settings component for configuring the AGE identity path or key.
 * Can be used standalone in the variables panel.
 * Stores the identity in .stackpanel/state/ (gitignored).
 */
"use client";

import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { AlertCircle, Key, Loader2 } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import type { AgeIdentityResponse } from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";

export function AgeIdentitySettings() {
	const { token } = useAgentContext();
	const agentClient = useAgentClient();
	const [inputValue, setInputValue] = useState("");
	const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(
		null,
	);
	const [isLoading, setIsLoading] = useState(true);
	const [isSaving, setIsSaving] = useState(false);
	const [error, setError] = useState<string | null>(null);

	// Load current identity on mount
	useEffect(() => {
		if (!token) return;
		const loadIdentity = async () => {
			try {
				const client = agentClient;
				const info = await client.getAgeIdentity();
				setIdentityInfo(info);
				if (info.type === "path") {
					setInputValue(info.value);
				} else if (info.type === "key") {
					setInputValue(""); // Don't show the actual key
				}
			} catch (err) {
				console.warn("Failed to load identity:", err);
			} finally {
				setIsLoading(false);
			}
		};
		loadIdentity();
	}, [token]);

	const handleSave = async () => {
		if (!token) return;
		setIsSaving(true);
		setError(null);
		try {
			const client = agentClient;
			const result = await client.setAgeIdentity(inputValue);
			setIdentityInfo(result);
			if (result.type === "path") {
				setInputValue(result.value);
			} else if (result.type === "key") {
				setInputValue(""); // Clear after storing
			}
			toast.success(result.type ? "Identity saved" : "Identity cleared");
		} catch (err) {
			const msg = err instanceof Error ? err.message : "Failed to save";
			setError(msg);
			toast.error(msg);
		} finally {
			setIsSaving(false);
		}
	};

	const handleClear = async () => {
		setInputValue("");
		if (!token) return;
		try {
			const client = agentClient;
			const result = await client.setAgeIdentity("");
			setIdentityInfo(result);
			toast.success("Identity cleared");
		} catch (err) {
			toast.error("Failed to clear identity");
		}
	};

	return (
		<div className="rounded-lg border border-border p-4 space-y-3">
			<div className="flex items-center gap-2">
				<Key className="h-4 w-4 text-muted-foreground" />
				<span className="text-sm font-medium">Decryption Key</span>
				{identityInfo?.type && (
					<span className="text-xs px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-600">
						{identityInfo.type === "key" ? "Key stored" : "Path configured"}
					</span>
				)}
			</div>
			<p className="text-xs text-muted-foreground">
				Enter a path to your private key file, or paste the key content
				directly. Stored in <code>.stackpanel/state/</code> (gitignored).
			</p>

			{error && (
				<div className="flex items-center gap-2 text-xs text-destructive">
					<AlertCircle className="h-3 w-3" />
					{error}
				</div>
			)}

			<div className="flex gap-2">
				<Input
					value={inputValue}
					onChange={(e) => setInputValue(e.target.value)}
					placeholder={
						identityInfo?.type === "key"
							? "(key already stored)"
							: "~/.ssh/id_ed25519 or paste AGE key"
					}
					className="font-mono text-sm flex-1"
					disabled={isLoading}
				/>
				<Button
					variant="outline"
					size="sm"
					onClick={handleSave}
					disabled={isSaving || isLoading}
				>
					{isSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}
				</Button>
				{identityInfo?.type && (
					<Button
						variant="ghost"
						size="sm"
						onClick={handleClear}
						disabled={isSaving}
					>
						Clear
					</Button>
				)}
			</div>

			<p className="text-[11px] text-muted-foreground/70">
				<strong>Paths:</strong> <code>~/.ssh/id_ed25519</code>,{" "}
				<code>~/.config/age/key.txt</code>
				<br />
				<strong>Keys:</strong> Paste content starting with{" "}
				<code>AGE-SECRET-KEY-</code> or <code>-----BEGIN</code>
			</p>
		</div>
	);
}
