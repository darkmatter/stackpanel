"use client";

import { Maximize2, Minimize2, Plus, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useAgentContext } from "@/lib/agent-provider";
import type { ExecResult } from "@/lib/agent";

interface TerminalLine {
	type: "input" | "output" | "error" | "success";
	content: string;
}

interface Tab {
	id: string;
	name: string;
	lines: TerminalLine[];
}

const initialTabs: Tab[] = [
	{
		id: "1",
		name: "main",
			lines: [
				{ type: "output", content: "Welcome to the Stackpanel terminal." },
				{ type: "output", content: "Run any shell command via the agent." },
				{ type: "output", content: "" },
			],
	},
];

export function TerminalPanel() {
	const [tabs, setTabs] = useState<Tab[]>(initialTabs);
	const [activeTab, setActiveTab] = useState("1");
	const [input, setInput] = useState("");
	const [isFullscreen, setIsFullscreen] = useState(false);
	const terminalRef = useRef<HTMLDivElement>(null);
	const inputRef = useRef<HTMLInputElement>(null);
	const { exec, isConnected } = useAgentContext();

	const currentTab = tabs.find((t) => t.id === activeTab);
	useEffect(() => {
		if (terminalRef.current) {
			terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
		}
	}, [currentTab?.lines]);

	const appendLines = useCallback(
		(tabId: string, lines: TerminalLine[]) => {
			setTabs((prev) =>
				prev.map((tab) =>
					tab.id === tabId
						? { ...tab, lines: [...tab.lines, ...lines] }
						: tab,
				),
			);
		},
		[],
	);

	const setTabLines = useCallback((tabId: string, lines: TerminalLine[]) => {
		setTabs((prev) =>
			prev.map((tab) => (tab.id === tabId ? { ...tab, lines } : tab)),
		);
	}, []);

	const streamExecOutput = useCallback(
		async (tabId: string, result: ExecResult) => {
			const outputLines = result.stdout
				.split("\n")
				.filter((line) => line !== "")
				.map((line) => ({ type: "output" as const, content: line }));
			const errorLines = result.stderr
				.split("\n")
				.filter((line) => line !== "")
				.map((line) => ({ type: "error" as const, content: line }));

			const lines =
				outputLines.length === 0 && errorLines.length === 0
					? [
							{
								type: result.exit_code === 0 ? "success" : "error",
								content:
									result.exit_code === 0
										? "✓ Command completed"
										: `Command exited with status ${result.exit_code}`,
							},
						]
					: [...outputLines, ...errorLines];

			for (const line of lines) {
				appendLines(tabId, [line]);
				await new Promise((resolve) => requestAnimationFrame(resolve));
			}
		},
		[appendLines],
	);

	const handleCommand = useCallback(
		async (command: string) => {
			if (!currentTab) return;

			const trimmedCommand = command.trim();
			if (!trimmedCommand) return;

			const tabId = currentTab.id;
			appendLines(tabId, [
				{ type: "input" as const, content: `$ ${command}` },
			]);
			setInput("");

			if (trimmedCommand.toLowerCase() === "clear") {
				setTabLines(tabId, []);
				return;
			}

				try {
					if (!isConnected) {
						throw new Error("Not connected to the agent");
					}

					const result = (await exec("bash", ["-lc", trimmedCommand])) as ExecResult;
					await streamExecOutput(tabId, result);
				} catch (err) {
				const message =
					err instanceof Error ? err.message : "Command failed";
				appendLines(tabId, [
					{ type: "error", content: message },
					{ type: "output", content: "" },
				]);
			}
		},
		[
				appendLines,
				currentTab,
				exec,
				isConnected,
				setTabLines,
				streamExecOutput,
			],
		);

	const addTab = () => {
		const newId = String(tabs.length + 1);
		setTabs([
			...tabs,
			{
				id: newId,
				name: `shell-${newId}`,
				lines: [
					{ type: "output", content: "New terminal session." },
					{ type: "output", content: "" },
				],
			},
		]);
		setActiveTab(newId);
	};

	const closeTab = (id: string) => {
		if (tabs.length === 1) return;
		const newTabs = tabs.filter((t) => t.id !== id);
		setTabs(newTabs);
		if (activeTab === id) {
			setActiveTab(newTabs[0].id);
		}
	};

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h2 className="font-semibold text-foreground text-xl">Terminal</h2>
					<p className="text-muted-foreground text-sm">
						Access your stack's CLI tools and scripts
					</p>
				</div>
				<Button
					className="gap-2 bg-transparent"
					onClick={() => setIsFullscreen(!isFullscreen)}
					size="sm"
					variant="outline"
				>
					{isFullscreen ? (
						<Minimize2 className="h-4 w-4" />
					) : (
						<Maximize2 className="h-4 w-4" />
					)}
					{isFullscreen ? "Exit Fullscreen" : "Fullscreen"}
				</Button>
			</div>

			<Card className={isFullscreen ? "fixed inset-4 z-50 flex flex-col" : ""}>
				<div className="flex items-center justify-between border-border border-b bg-secondary/50 px-2">
					<Tabs onValueChange={setActiveTab} value={activeTab}>
						<TabsList className="h-10 bg-transparent p-0">
							{tabs.map((tab) => (
								<div className="group relative" key={tab.id}>
									<TabsTrigger
										className="h-10 rounded-none border-transparent border-b-2 px-4 data-[state=active]:border-accent data-[state=active]:bg-transparent"
										value={tab.id}
									>
										{tab.name}
									</TabsTrigger>
									{tabs.length > 1 && (
										<button
											className="-translate-y-1/2 absolute top-1/2 right-1 opacity-0 hover:text-destructive group-hover:opacity-100"
											onClick={(e) => {
												e.stopPropagation();
												closeTab(tab.id);
											}}
										>
											<X className="h-3 w-3" />
										</button>
									)}
								</div>
							))}
						</TabsList>
					</Tabs>
					<Button
						className="h-8 w-8"
						onClick={addTab}
						size="icon"
						variant="ghost"
					>
						<Plus className="h-4 w-4" />
					</Button>
				</div>

				<CardContent
					className={`flex-1 p-0 ${isFullscreen ? "overflow-hidden" : ""}`}
				>
					<div
						className={`overflow-auto bg-background p-4 font-mono text-sm ${
							isFullscreen ? "h-[calc(100vh-12rem)]" : "h-96"
						}`}
						onClick={() => inputRef.current?.focus()}
						ref={terminalRef}
					>
						{currentTab?.lines.map((line, i) => (
							<div
								className={
									line.type === "input"
										? "text-foreground"
										: line.type === "error"
											? "text-destructive"
											: line.type === "success"
												? "text-accent"
												: "text-muted-foreground"
								}
								key={i}
							>
								{line.content || "\u00A0"}
							</div>
						))}

						<div className="flex items-center">
							<span className="mr-2 text-accent">$</span>
							<input
								autoFocus
								className="flex-1 bg-transparent text-foreground outline-none"
								onChange={(e) => setInput(e.target.value)}
								onKeyDown={(e) => {
								if (e.key === "Enter" && input.trim()) {
									handleCommand(input);
								}
							}}
								ref={inputRef}
								type="text"
								value={input}
							/>
						</div>
					</div>
				</CardContent>
			</Card>

			<Card>
				<CardContent className="p-4">
					<p className="text-muted-foreground text-sm">
						Enter any shell command to run via the agent.
					</p>
				</CardContent>
			</Card>
		</div>
	);
}
