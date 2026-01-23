"use client";

import { Button } from "@ui/button";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@ui/popover";
import {
	Tooltip,
	TooltipContent,
	TooltipTrigger,
} from "@ui/tooltip";
import {
	AlertTriangle,
	CheckCircle2,
	Loader2,
	RefreshCw,
	Terminal,
} from "lucide-react";
import { useState } from "react";
import { useShellStatus, useRebuildShell } from "@/lib/use-agent";
import { useShellStatusSSE } from "@/lib/use-sse";
import { cn } from "@/lib/utils";
import { useAgentContext } from "@/lib/agent-provider";

/**
 * Shell status indicator for the dashboard header.
 * Shows whether the devshell is stale and provides a rebuild button.
 */
export function ShellStatus() {
	const { isConnected } = useAgentContext();
	const { data: status, isLoading, refetch } = useShellStatus();
	const { rebuild, isRebuilding, output, error, clearError } = useRebuildShell();
	const [showOutput, setShowOutput] = useState(false);

	// Subscribe to SSE for real-time updates
	const { isStale: sseStale, isRebuilding: sseRebuilding, lastChangedFile } = useShellStatusSSE(() => {
		// Refetch status when SSE indicates change
		refetch();
	});

	// Combine query data with SSE data (SSE takes precedence for real-time)
	const isStale = sseStale || status?.stale || false;
	const isCurrentlyRebuilding = sseRebuilding || isRebuilding || status?.rebuilding || false;
	const changedFiles = status?.changedFiles ?? [];

	// Don't show if not connected
	if (!isConnected) {
		return null;
	}

	// Loading state
	if (isLoading && !status) {
		return (
			<div className="flex items-center gap-2 text-muted-foreground text-xs">
				<Loader2 className="h-3 w-3 animate-spin" />
			</div>
		);
	}

	// Rebuilding state
	if (isCurrentlyRebuilding) {
		return (
			<Popover open={showOutput} onOpenChange={setShowOutput}>
				<PopoverTrigger asChild>
					<Button
						variant="ghost"
						size="sm"
						className="h-8 gap-2 text-blue-500 hover:text-blue-600"
					>
						<Loader2 className="h-3.5 w-3.5 animate-spin" />
						<span className="text-xs">Rebuilding...</span>
					</Button>
				</PopoverTrigger>
				<PopoverContent align="end" className="w-96">
					<div className="space-y-3">
						<div className="flex items-center gap-2">
							<Terminal className="h-4 w-4 text-muted-foreground" />
							<span className="font-medium text-sm">Shell Rebuild Output</span>
						</div>
						<div className="max-h-64 overflow-y-auto rounded-md bg-secondary/50 p-3 font-mono text-xs">
							{output.length === 0 ? (
								<span className="text-muted-foreground">Waiting for output...</span>
							) : (
								output.map((line, i) => (
									<div key={i} className="whitespace-pre-wrap break-all">
										{line}
									</div>
								))
							)}
						</div>
					</div>
				</PopoverContent>
			</Popover>
		);
	}

	// Stale state - show warning with rebuild button
	if (isStale) {
		return (
			<Popover>
				<PopoverTrigger asChild>
					<Button
						variant="ghost"
						size="sm"
						className={cn(
							"h-8 gap-2",
							"text-yellow-600 hover:text-yellow-700 dark:text-yellow-500 dark:hover:text-yellow-400"
						)}
					>
						<AlertTriangle className="h-3.5 w-3.5" />
						<span className="text-xs">Shell Stale</span>
					</Button>
				</PopoverTrigger>
				<PopoverContent align="end" className="w-80">
					<div className="space-y-4">
						<div className="space-y-2">
							<div className="flex items-center gap-2">
								<AlertTriangle className="h-4 w-4 text-yellow-500" />
								<span className="font-medium text-sm">Devshell is Stale</span>
							</div>
							<p className="text-muted-foreground text-xs">
								Nix configuration has changed since the shell was last built.
								Rebuild to apply changes.
							</p>
						</div>

						{(changedFiles.length > 0 || lastChangedFile) && (
							<div className="space-y-1">
								<span className="text-muted-foreground text-xs font-medium">
									Changed files:
								</span>
								<div className="max-h-24 overflow-y-auto rounded bg-secondary/50 p-2">
									{lastChangedFile && !changedFiles.includes(lastChangedFile) && (
										<div className="font-mono text-xs text-muted-foreground truncate">
											{lastChangedFile}
										</div>
									)}
									{changedFiles.map((file) => (
										<div
											key={file}
											className="font-mono text-xs text-muted-foreground truncate"
										>
											{file}
										</div>
									))}
								</div>
							</div>
						)}

						{error && (
							<div className="rounded bg-destructive/10 p-2 text-destructive text-xs">
								{error}
								<Button
									variant="ghost"
									size="sm"
									className="ml-2 h-5 px-1 text-xs"
									onClick={clearError}
								>
									Dismiss
								</Button>
							</div>
						)}

						<div className="flex gap-2">
							<Button
								size="sm"
								className="flex-1 gap-2"
								onClick={() => {
									setShowOutput(true);
									rebuild("devshell");
								}}
							>
								<RefreshCw className="h-3.5 w-3.5" />
								Rebuild Shell
							</Button>
							<Tooltip>
								<TooltipTrigger asChild>
									<Button
										size="sm"
										variant="outline"
										onClick={() => {
											setShowOutput(true);
											rebuild("nix");
										}}
									>
										<Terminal className="h-3.5 w-3.5" />
									</Button>
								</TooltipTrigger>
								<TooltipContent>
									<p>Use nix develop</p>
								</TooltipContent>
							</Tooltip>
						</div>
					</div>
				</PopoverContent>
			</Popover>
		);
	}

	// Fresh state - just show a small indicator
	return (
		<Tooltip>
			<TooltipTrigger asChild>
				<div className="flex items-center gap-1.5 text-emerald-500 text-xs cursor-default">
					<CheckCircle2 className="h-3.5 w-3.5" />
					<span className="hidden sm:inline">Shell OK</span>
				</div>
			</TooltipTrigger>
			<TooltipContent>
				<p>Devshell is up to date</p>
			</TooltipContent>
		</Tooltip>
	);
}
