"use client";

import { Maximize2, Minimize2, Plus, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";

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
			{ type: "output", content: "Welcome to StackPanel Terminal" },
			{ type: "output", content: "Type 'help' for available commands" },
			{ type: "output", content: "" },
			{ type: "input", content: "$ x status" },
			{ type: "success", content: "✓ All services operational" },
			{ type: "output", content: "  api-gateway      running   3/3 replicas" },
			{ type: "output", content: "  auth-service     running   2/2 replicas" },
			{ type: "output", content: "  worker-service   running   4/4 replicas" },
			{ type: "output", content: "" },
		],
	},
];

const commandResponses: Record<string, TerminalLine[]> = {
	help: [
		{ type: "output", content: "Available commands:" },
		{
			type: "output",
			content:
				"  create-app <name>     Create a new app with turborepo template",
		},
		{
			type: "output",
			content: "  x install <package>   Install and configure a package",
		},
		{
			type: "output",
			content: "  x status              Show status of all services",
		},
		{ type: "output", content: "  x deploy <service>    Deploy a service" },
		{
			type: "output",
			content: "  x logs <service>      Tail logs for a service",
		},
		{
			type: "output",
			content: "  db connect <name>     Connect to a database",
		},
		{ type: "output", content: "  secrets list          List all secrets" },
		{ type: "output", content: "  secrets get <key>     Get a secret value" },
		{ type: "output", content: "" },
	],
	"create-app": [
		{ type: "success", content: "✓ Creating new app..." },
		{ type: "output", content: "  Cloning turborepo template..." },
		{ type: "success", content: "✓ Created repo acme-corp/my-app" },
		{ type: "success", content: "✓ Applied stack configuration" },
		{ type: "success", content: "✓ Configured CI/CD pipeline" },
		{ type: "success", content: "✓ Added to StackPanel" },
		{ type: "output", content: "" },
		{ type: "output", content: "Next steps:" },
		{ type: "output", content: "  cd my-app && pnpm install" },
		{ type: "output", content: "  pnpm dev" },
		{ type: "output", content: "" },
	],
	"x install neon": [
		{ type: "success", content: "✓ Installing Neon..." },
		{ type: "output", content: "  Adding @neondatabase/serverless..." },
		{ type: "success", content: "✓ Added DATABASE_URL to secrets" },
		{ type: "success", content: "✓ Created db/schema.ts" },
		{ type: "success", content: "✓ Created db/migrations/" },
		{ type: "output", content: "" },
		{
			type: "output",
			content: "Neon is ready! Run 'db migrate' to apply migrations.",
		},
		{ type: "output", content: "" },
	],
	"x status": [
		{ type: "success", content: "✓ All services operational" },
		{ type: "output", content: "  api-gateway      running   3/3 replicas" },
		{ type: "output", content: "  auth-service     running   2/2 replicas" },
		{ type: "output", content: "  worker-service   running   4/4 replicas" },
		{ type: "output", content: "  frontend         running   2/2 replicas" },
		{ type: "output", content: "" },
	],
	"secrets list": [
		{ type: "output", content: "Secrets (encrypted with age):" },
		{
			type: "output",
			content: "  DATABASE_URL        production   rotated 3d ago",
		},
		{
			type: "output",
			content: "  REDIS_URL           production   rotated 1w ago",
		},
		{
			type: "output",
			content: "  JWT_SECRET          production   rotated 30d ago",
		},
		{
			type: "output",
			content: "  STRIPE_SECRET_KEY   production   rotated 60d ago",
		},
		{ type: "output", content: "" },
	],
	"db connect main-postgres": [
		{ type: "success", content: "✓ Connecting to main-postgres..." },
		{ type: "output", content: "  Using mTLS certificate from internal CA" },
		{ type: "success", content: "✓ Connected to PostgreSQL 15.2" },
		{ type: "output", content: "" },
		{ type: "output", content: "psql (15.2)" },
		{ type: "output", content: 'Type "help" for help.' },
		{ type: "output", content: "" },
		{ type: "output", content: "main-postgres=# " },
	],
	clear: [],
};

export function TerminalPanel() {
	const [tabs, setTabs] = useState<Tab[]>(initialTabs);
	const [activeTab, setActiveTab] = useState("1");
	const [input, setInput] = useState("");
	const [isFullscreen, setIsFullscreen] = useState(false);
	const terminalRef = useRef<HTMLDivElement>(null);
	const inputRef = useRef<HTMLInputElement>(null);

	const currentTab = tabs.find((t) => t.id === activeTab);

	useEffect(() => {
		if (terminalRef.current) {
			terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
		}
	}, [currentTab?.lines]);

	const handleCommand = (command: string) => {
		if (!currentTab) return;

		const trimmedCommand = command.trim().toLowerCase();

		setTabs((prev) =>
			prev.map((tab) => {
				if (tab.id !== activeTab) return tab;

				const newLines = [
					...tab.lines,
					{ type: "input" as const, content: `$ ${command}` },
				];

				if (trimmedCommand === "clear") {
					return { ...tab, lines: [] };
				}

				const response = commandResponses[trimmedCommand] ||
					commandResponses[trimmedCommand.split(" ").slice(0, 2).join(" ")] ||
					commandResponses[trimmedCommand.split(" ")[0]] || [
						{
							type: "error" as const,
							content: `Command not found: ${command}`,
						},
						{
							type: "output" as const,
							content: "Type 'help' for available commands",
						},
						{ type: "output" as const, content: "" },
					];

				return { ...tab, lines: [...newLines, ...response] };
			}),
		);

		setInput("");
	};

	const addTab = () => {
		const newId = String(tabs.length + 1);
		setTabs([
			...tabs,
			{
				id: newId,
				name: `shell-${newId}`,
				lines: [
					{ type: "output", content: "Welcome to StackPanel Terminal" },
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
					<p className="mb-3 text-muted-foreground text-sm">
						Try these commands:
					</p>
					<div className="flex flex-wrap gap-2">
						{[
							"help",
							"x status",
							"create-app my-app",
							"x install neon",
							"secrets list",
							"db connect main-postgres",
						].map((cmd) => (
							<Button
								className="bg-transparent font-mono text-xs"
								key={cmd}
								onClick={() => {
									setInput(cmd);
									inputRef.current?.focus();
								}}
								size="sm"
								variant="outline"
							>
								{cmd}
							</Button>
						))}
					</div>
				</CardContent>
			</Card>
		</div>
	);
}
