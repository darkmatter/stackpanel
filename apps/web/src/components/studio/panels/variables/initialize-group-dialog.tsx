"use client";

import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@ui/dialog";
import { CheckCircle2, Copy, Key, Loader2, Terminal } from "lucide-react";
import { useCallback, useState } from "react";
import { toast } from "sonner";
import { useAgentClient } from "@/lib/agent-provider";
import { usePatchNixData, useRefreshNixConfig } from "@/lib/use-agent";

interface InitGroupResult {
	group: string;
	publicKey: string;
	ssmPath: string;
	dryRun: boolean;
	success?: boolean;
}

interface InitializeGroupDialogProps {
	groupName: string;
	ssmPath: string;
	isReinitialize?: boolean;
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onSuccess?: () => void;
}

type InitState =
	| { step: "confirm" }
	| { step: "running" }
	| { step: "writing-config" }
	| { step: "success"; publicKey: string }
	| { step: "error"; message: string };

export function InitializeGroupDialog({
	groupName,
	ssmPath,
	isReinitialize = false,
	open,
	onOpenChange,
	onSuccess,
}: InitializeGroupDialogProps) {
	const agentClient = useAgentClient();
	const patchNixData = usePatchNixData();
	const refreshConfig = useRefreshNixConfig();
	const [state, setState] = useState<InitState>({ step: "confirm" });
	const [output, setOutput] = useState("");

	const handleInitialize = useCallback(async () => {
		if (!agentClient) {
			toast.error("Not connected to agent");
			return;
		}

		setState({ step: "running" });
		setOutput("");

		try {
			// secrets-init-group is in devshell packages; the agent's executor
			// merges the devshell PATH so the binary is available directly.
			const result = await agentClient.exec({
				command: "secrets-init-group",
				args: [groupName, "--yes", "--json"],
			});

			// Capture stderr as output log
			if (result.stderr) {
				setOutput(result.stderr);
			}

			if (result.exit_code !== 0) {
				const errorMsg =
					result.stderr || result.stdout || "Unknown error";
				setState({ step: "error", message: errorMsg });
				return;
			}

			// Parse JSON output from stdout
			let initResult: InitGroupResult;
			try {
				initResult = JSON.parse(result.stdout);
			} catch {
				// Fallback: try to extract public key from output
				const match = result.stdout.match(
					/Public key:\s+(age1[a-z0-9]+)/,
				);
				if (match) {
					initResult = {
						group: groupName,
						publicKey: match[1],
						ssmPath,
						dryRun: false,
						success: true,
					};
				} else {
					setState({
						step: "error",
						message:
							"Could not parse output. The key may have been stored in SSM but the public key was not captured.",
					});
					return;
				}
			}

			// Step 2: Write the public key back to config
			setState({ step: "writing-config" });

			try {
				await patchNixData.mutateAsync({
					entity: "secrets",
					key: "",
					path: `groups.${groupName}.agePub`,
					value: JSON.stringify(initResult.publicKey),
					valueType: "string",
				});
			} catch (patchError) {
				// If patchNixData fails (e.g., key="" not supported for data schemas),
				// show the public key so the user can manually add it
				console.warn(
					"patchNixData failed, showing manual instructions:",
					patchError,
				);
				setState({ step: "success", publicKey: initResult.publicKey });
				toast.warning(
					"Key stored in SSM but could not auto-update config. Copy the public key below.",
				);
				return;
			}

			// Step 3: Refresh nix config to pick up the change
			try {
				await refreshConfig.mutateAsync();
			} catch {
				// Non-critical - config will refresh on next poll
			}

			setState({ step: "success", publicKey: initResult.publicKey });
			toast.success(
				`Group "${groupName}" initialized and config updated`,
			);
			onSuccess?.();
		} catch (err) {
			const message =
				err instanceof Error ? err.message : "Unknown error";
			setState({ step: "error", message });
		}
	}, [
		agentClient,
		groupName,
		ssmPath,
		patchNixData,
		refreshConfig,
		onSuccess,
	]);

	const handleCopyPublicKey = useCallback(
		(key: string) => {
			navigator.clipboard.writeText(key);
			toast.success("Public key copied to clipboard");
		},
		[],
	);

	const handleClose = useCallback(() => {
		setState({ step: "confirm" });
		setOutput("");
		onOpenChange(false);
	}, [onOpenChange]);

	return (
		<Dialog open={open} onOpenChange={handleClose}>
			<DialogContent className="sm:max-w-lg">
				<DialogHeader>
					<DialogTitle className="flex items-center gap-2">
						<Key className="h-5 w-5" />
						{isReinitialize ? "Re-initialize" : "Initialize"} Group:{" "}
						{groupName}
					</DialogTitle>
					<DialogDescription>
						{isReinitialize
							? "Generate a new AGE keypair and store the private key in SSM. This will replace the existing key."
							: "Generate an AGE keypair and store the private key in AWS SSM Parameter Store."}
					</DialogDescription>
				</DialogHeader>

				{state.step === "confirm" && (
					<div className="space-y-4">
						<div className="rounded-lg border border-border bg-muted/50 p-4 space-y-3">
							<div className="space-y-1">
								<p className="text-xs font-medium text-muted-foreground">
									Group
								</p>
								<code className="text-sm font-mono font-semibold">
									{groupName}
								</code>
							</div>
							<div className="space-y-1">
								<p className="text-xs font-medium text-muted-foreground">
									SSM Path
								</p>
								<code className="text-sm font-mono text-muted-foreground break-all">
									{ssmPath}
								</code>
							</div>
						</div>

						<div className="text-sm text-muted-foreground space-y-2">
							<p>This will:</p>
							<ol className="list-decimal ml-5 space-y-1">
								<li>Generate a new AGE keypair</li>
								<li>
									Store the private key as a SecureString in
									SSM at the path above
								</li>
								<li>
									Save the public key to your project config
								</li>
							</ol>
						</div>

						{isReinitialize && (
							<div className="rounded-lg border border-amber-500/20 bg-amber-500/5 p-3">
								<p className="text-sm text-amber-600 dark:text-amber-400">
									Warning: Re-initializing will generate a new
									keypair. Secrets encrypted to the old key
									will need to be re-encrypted.
								</p>
							</div>
						)}

						<div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-3">
							<p className="text-sm text-blue-600 dark:text-blue-400">
								Requires valid AWS credentials with SSM write
								access.
							</p>
						</div>
					</div>
				)}

				{(state.step === "running" ||
					state.step === "writing-config") && (
					<div className="space-y-4">
						<div className="flex items-center gap-3 p-4">
							<Loader2 className="h-5 w-5 animate-spin text-primary" />
							<div>
								<p className="text-sm font-medium">
									{state.step === "running"
										? "Generating keypair and storing in SSM..."
										: "Updating project config..."}
								</p>
								<p className="text-xs text-muted-foreground">
									This may take a few seconds
								</p>
							</div>
						</div>
						{output && (
							<pre className="rounded-lg bg-muted p-3 text-xs font-mono text-muted-foreground overflow-x-auto max-h-32 overflow-y-auto">
								{output}
							</pre>
						)}
					</div>
				)}

				{state.step === "success" && (
					<div className="space-y-4">
						<div className="flex items-center gap-3 p-4 rounded-lg border border-green-500/20 bg-green-500/5">
							<CheckCircle2 className="h-5 w-5 text-green-500 shrink-0" />
							<div className="min-w-0">
								<p className="text-sm font-medium text-green-600 dark:text-green-400">
									Group initialized successfully
								</p>
								<p className="text-xs text-muted-foreground mt-1">
									Private key stored in SSM. Public key saved
									to config.
								</p>
							</div>
						</div>

						<div className="space-y-2">
							<p className="text-xs font-medium text-muted-foreground">
								Public Key
							</p>
							<div className="flex items-center gap-2">
								<code className="flex-1 text-xs font-mono bg-muted px-3 py-2 rounded break-all">
									{state.publicKey}
								</code>
								<Button
									variant="ghost"
									size="sm"
									onClick={() =>
										handleCopyPublicKey(state.publicKey)
									}
								>
									<Copy className="h-3.5 w-3.5" />
								</Button>
							</div>
						</div>

						{output && (
							<details className="text-xs">
								<summary className="cursor-pointer text-muted-foreground hover:text-foreground">
									<Terminal className="h-3 w-3 inline mr-1" />
									Show output
								</summary>
								<pre className="mt-2 rounded-lg bg-muted p-3 font-mono text-muted-foreground overflow-x-auto max-h-32 overflow-y-auto">
									{output}
								</pre>
							</details>
						)}
					</div>
				)}

				{state.step === "error" && (
					<div className="space-y-4">
						<div className="rounded-lg border border-destructive/20 bg-destructive/5 p-4">
							<p className="text-sm font-medium text-destructive mb-2">
								Initialization failed
							</p>
							<pre className="text-xs font-mono text-muted-foreground whitespace-pre-wrap break-all max-h-40 overflow-y-auto">
								{state.message}
							</pre>
						</div>
					</div>
				)}

				<DialogFooter>
					{state.step === "confirm" && (
						<>
							<Button
								variant="outline"
								onClick={handleClose}
							>
								Cancel
							</Button>
							<Button onClick={handleInitialize}>
								<Key className="h-4 w-4 mr-2" />
								{isReinitialize
									? "Re-initialize"
									: "Initialize"}
							</Button>
						</>
					)}
					{(state.step === "success" ||
						state.step === "error") && (
						<Button onClick={handleClose}>
							{state.step === "success" ? "Done" : "Close"}
						</Button>
					)}
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
