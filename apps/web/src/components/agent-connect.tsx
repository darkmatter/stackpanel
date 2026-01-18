"use client";

import { Button } from "@ui/button";
import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@ui/card";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@ui/popover";
import {
	AlertCircle,
	CheckCircle2,
	Loader2,
	Settings,
	Terminal,
	Unplug,
	Wifi,
} from "lucide-react";
import { useEffect, useState } from "react";
import { useAgentContext } from "@/lib/agent-provider";

const AGENT_CONFIG_KEY = "stackpanel-agent-config";

interface AgentConfig {
	host: string;
	port: number;
}

function getStoredConfig(): AgentConfig {
	if (typeof window === "undefined") {
		return { host: "localhost", port: 9876 };
	}
	try {
		const stored = localStorage.getItem(AGENT_CONFIG_KEY);
		if (stored) {
			return JSON.parse(stored);
		}
	} catch {
		// Ignore
	}
	return { host: "localhost", port: 9876 };
}

function saveConfig(config: AgentConfig) {
	if (typeof window !== "undefined") {
		localStorage.setItem(AGENT_CONFIG_KEY, JSON.stringify(config));
	}
}

interface AgentConnectProps {
	onConnected?: () => void;
	overlay?: boolean;
}

export function AgentConnect({ onConnected }: AgentConnectProps) {
	const [config, setConfig] = useState<AgentConfig>(getStoredConfig);
	const [tempHost, setTempHost] = useState(config.host);
	const [tempPort, setTempPort] = useState(String(config.port));
	const [settingsOpen, setSettingsOpen] = useState(false);
	const {
		healthStatus,
		isConnected,
		projectRoot,
		pair,
		clearPairing,
		connect,
	} = useAgentContext();

	const [pairingToken, setPairingToken] = useState("");
	const [isPairing, setIsPairing] = useState(false);
	const [pairingError, setPairingError] = useState<string | null>(null);
	const [_dialogOpen, setDialogOpen] = useState(false);

	// Sync temp values when config changes
	useEffect(() => {
		setTempHost(config.host);
		setTempPort(String(config.port));
	}, [config]);

	const handleSaveSettings = () => {
		const newPort = Number.parseInt(tempPort, 10);
		if (Number.isNaN(newPort) || newPort < 1 || newPort > 65535) {
			return;
		}

		const newConfig = { host: tempHost || "localhost", port: newPort };
		setConfig(newConfig);
		saveConfig(newConfig);
		setSettingsOpen(false);

		// Refresh connection with new settings
		setTimeout(() => clearPairing(), 100);
	};

	const handlePair = async () => {
		if (!pairingToken.trim()) {
			setPairingError("Please enter a pairing token");
			return;
		}

		setIsPairing(true);
		setPairingError(null);

		try {
			await pair();
			setDialogOpen(false);
			setPairingToken("");
			onConnected?.();
		} catch (err) {
			setPairingError(
				err instanceof Error ? err.message : "Failed to pair with agent",
			);
		} finally {
			setIsPairing(false);
		}
	};

	const handleDisconnect = () => {
		clearPairing();
	};

	const SettingsButton = () => (
		<Popover onOpenChange={setSettingsOpen} open={settingsOpen}>
			<PopoverTrigger asChild>
				<Button
					className="h-8 w-8 text-muted-foreground hover:text-foreground"
					size="icon"
					variant="ghost"
				>
					<Settings className="h-4 w-4" />
				</Button>
			</PopoverTrigger>
			<PopoverContent align="end" className="w-72">
				<div className="grid gap-4">
					<div className="space-y-2">
						<h4 className="font-medium leading-none">Agent Connection</h4>
						<p className="text-muted-foreground text-sm">
							Configure the agent host and port.
						</p>
					</div>
					<div className="grid gap-3">
						<div className="grid gap-2">
							<Label htmlFor="agent-host">Host</Label>
							<Input
								id="agent-host"
								onChange={(e) => setTempHost(e.target.value)}
								placeholder="localhost"
								value={tempHost}
							/>
						</div>
						<div className="grid gap-2">
							<Label htmlFor="agent-port">Port</Label>
							<Input
								id="agent-port"
								onChange={(e) => setTempPort(e.target.value)}
								placeholder="9876"
								type="number"
								value={tempPort}
							/>
						</div>
						<Button onClick={handleSaveSettings} size="sm">
							Save & Reconnect
						</Button>
					</div>
					<p className="text-muted-foreground text-xs">
						Current: {config.host}:{config.port}
					</p>
				</div>
			</PopoverContent>
		</Popover>
	);

	if (healthStatus === "checking") {
		return (
			<Card className="border-border/50">
				<CardContent className="flex items-center justify-between p-4">
					<div className="flex items-center gap-3">
						<Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
						<span className="text-muted-foreground text-sm">
							Checking for local agent at {config.host}:{config.port}...
						</span>
					</div>
					<SettingsButton />
				</CardContent>
			</Card>
		);
	}

	if (healthStatus === "unavailable") {
		return (
			<Card className="border-destructive/30 bg-destructive/5">
				<CardHeader className="pb-3">
					<div className="flex items-start justify-between">
						<CardTitle className="flex items-center gap-2 text-base">
							<AlertCircle className="h-5 w-5 text-destructive" />
							Agent Not Running
						</CardTitle>
						<SettingsButton />
					</div>
					<CardDescription>
						The StackPanel agent is not running at {config.host}:{config.port}.
						Install the CLI and start the agent to enable local operations.
					</CardDescription>
				</CardHeader>
				<CardContent className="space-y-4">
					{/* Install CLI */}
					<div className="space-y-3">
						<p className="font-medium text-foreground text-sm">
							1. Install the CLI
						</p>
						<div className="rounded-lg border border-border bg-secondary/50 p-3 space-y-2">
							<div className="flex items-center gap-2">
								<Terminal className="h-4 w-4 text-muted-foreground" />
								<span className="text-xs text-muted-foreground">
									Using Nix (recommended)
								</span>
							</div>
							<code className="block rounded bg-background p-2 font-mono text-muted-foreground text-xs">
								nix profile install github:darkmatter/stackpanel
							</code>
						</div>
						<div className="rounded-lg border border-border bg-secondary/50 p-3 space-y-2">
							<div className="flex items-center gap-2">
								<Terminal className="h-4 w-4 text-muted-foreground" />
								<span className="text-xs text-muted-foreground">
									Using Homebrew
								</span>
							</div>
							<code className="block rounded bg-background p-2 font-mono text-muted-foreground text-xs">
								brew install darkmatter/tap/stackpanel
							</code>
						</div>
					</div>

					{/* Start agent */}
					<div className="space-y-3">
						<p className="font-medium text-foreground text-sm">
							2. Start the agent
						</p>
						<div className="rounded-lg border border-border bg-secondary/50 p-3">
							<code className="block rounded bg-background p-2 font-mono text-muted-foreground text-xs">
								stackpanel agent
								{config.port !== 9876 ? ` --port ${config.port}` : ""}
							</code>
						</div>
					</div>

					<Button
						onClick={() => {
							clearPairing();
							connect();
						}}
						size="sm"
						variant="outline"
					>
						<Wifi className="mr-2 h-4 w-4" />
						Retry Connection
					</Button>
				</CardContent>
			</Card>
		);
	}

	if (isConnected) {
		return (
			<Card className="border-emerald-500/30 bg-emerald-500/5">
				<CardContent className="flex items-center justify-between p-4">
					<div className="flex items-center gap-3">
						<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-emerald-500/20">
							<CheckCircle2 className="h-5 w-5 text-emerald-500" />
						</div>
						<div>
							<p className="font-medium text-foreground text-sm">
								Connected to Agent
							</p>
							<p className="text-muted-foreground text-xs">
								{projectRoot || `${config.host}:${config.port}`}
							</p>
						</div>
					</div>
					<div className="flex items-center gap-1">
						<SettingsButton />
						<Button onClick={handleDisconnect} size="sm" variant="ghost">
							<Unplug className="mr-2 h-4 w-4" />
							Disconnect
						</Button>
					</div>
				</CardContent>
			</Card>
		);
	}

	// Available but not paired
	return (
		<Card className="border-yellow-500/30 bg-yellow-500/5">
			<CardHeader className="pb-3">
				<div className="flex items-start justify-between">
					<CardTitle className="flex items-center gap-2 text-base">
						<Terminal className="h-5 w-5 text-yellow-500" />
						Agent Available
					</CardTitle>
					<SettingsButton />
				</div>
				<CardDescription>
					The agent is running at {config.host}:{config.port}. Enter your
					pairing token to connect.
				</CardDescription>
			</CardHeader>
			<CardContent className="space-y-4">
				{projectRoot && (
					<p className="text-muted-foreground text-xs">
						Project: <code className="text-foreground">{projectRoot}</code>
					</p>
				)}

				{/* This dialog is currently unused, keeping it here because it could be useful in the future */}
				<Dialog open={false}>
					<DialogTrigger asChild>
						<Button
							className="gap-2 bg-emerald-500 text-emerald-500-foreground hover:bg-emerald-500/90"
							onClick={() => {
								pair();
							}}
						>
							<Wifi className="h-4 w-4" />
							Connect to Agent
						</Button>
					</DialogTrigger>
					<DialogContent>
						<DialogHeader>
							<DialogTitle>Pair with Local Agent</DialogTitle>
							<DialogDescription>
								Enter the pairing token shown in your terminal when the agent
								started.
							</DialogDescription>
						</DialogHeader>
						<div className="grid gap-4 py-4">
							<div className="grid gap-2">
								<Label htmlFor="pairing-token">Pairing Token</Label>
								<Input
									className="font-mono"
									id="pairing-token"
									onChange={(e) => setPairingToken(e.target.value)}
									onKeyDown={(e) => {
										if (e.key === "Enter") {
											handlePair();
										}
									}}
									placeholder="Enter token from terminal..."
									value={pairingToken}
								/>
								{pairingError && (
									<p className="text-destructive text-sm">{pairingError}</p>
								)}
							</div>
							<div className="rounded-lg border border-border bg-secondary/30 p-3">
								<p className="text-muted-foreground text-sm">
									The pairing token is displayed when you run{" "}
									<code className="text-foreground">stackpanel agent</code>. It
									looks like:{" "}
									<code className="text-emerald-500">
										a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
									</code>
								</p>
							</div>
						</div>
						<DialogFooter>
							<Button onClick={() => setDialogOpen(false)} variant="outline">
								Cancel
							</Button>
							<Button
								className="bg-emerald-500 text-emerald-500-foreground hover:bg-emerald-500/90"
								disabled={isPairing}
								onClick={handlePair}
							>
								{isPairing && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
								Pair
							</Button>
						</DialogFooter>
					</DialogContent>
				</Dialog>
			</CardContent>
		</Card>
	);
}

/**
 * Compact status indicator for headers/sidebars
 *
 * Uses token presence (not WebSocket state) to determine "connected" status,
 * since most functionality uses HTTP+tRPC with token auth.
 */
export function AgentStatus() {
	const { healthStatus, token } = useAgentContext();

	// Agent health check in progress
	if (healthStatus === "checking") {
		return (
			<div className="flex items-center gap-2 text-muted-foreground text-xs">
				<Loader2 className="h-3 w-3 animate-spin" />
				<span>Checking...</span>
			</div>
		);
	}

	// Agent not reachable
	if (healthStatus === "unavailable") {
		return (
			<div className="flex items-center gap-2 text-destructive text-xs">
				<div className="h-2 w-2 rounded-full bg-destructive" />
				<span>Agent offline</span>
			</div>
		);
	}

	// Agent available and we have a valid token (paired)
	if (token) {
		return (
			<div className="flex items-center gap-2 text-emerald-500 text-xs">
				<div className="h-2 w-2 rounded-full bg-emerald-500" />
				<span>Connected</span>
			</div>
		);
	}

	// Agent available but no token (not paired)
	return (
		<div className="flex items-center gap-2 text-yellow-500 text-xs">
			<div className="h-2 w-2 rounded-full bg-yellow-500" />
			<span>Not paired</span>
		</div>
	);
}
