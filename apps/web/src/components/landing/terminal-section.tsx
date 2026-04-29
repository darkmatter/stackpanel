"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

type TerminalLine = {
	text: string;
	tone?: "info" | "success" | "warning" | "muted" | "highlight";
};

type Tab = {
	id: string;
	label: string;
	prompt: string;
	command: string;
	lines: TerminalLine[];
};

const tabs: Tab[] = [
	{
		id: "init",
		label: "Bootstrap",
		prompt: "~/myapp $",
		command: "nix flake init -t github:darkmatter/stackpanel#default",
		lines: [
			{ text: "→ Cloning template into ./", tone: "info" },
			{ text: "✓ flake.nix written", tone: "success" },
			{ text: "✓ .stack/config.nix written", tone: "success" },
			{ text: "✓ .envrc written (direnv)", tone: "success" },
			{ text: "" },
			{ text: "Next:", tone: "muted" },
			{ text: "  direnv allow             # build & enter the devshell", tone: "muted" },
			{ text: "  dev                      # start every app + service", tone: "muted" },
			{ text: "  stackpanel studio        # open Studio in your browser", tone: "muted" },
		],
	},
	{
		id: "shell",
		label: "Enter devshell",
		prompt: "~/myapp $",
		command: "direnv allow",
		lines: [
			{ text: "direnv: loading .envrc", tone: "muted" },
			{ text: "→ Evaluating .stack/config.nix", tone: "info" },
			{ text: "→ Building devshell (cached: 142 / 144 derivations)", tone: "info" },
			{ text: "✓ Toolchain ready: bun 1.x · go 1.25 · postgres 16", tone: "success" },
			{ text: "✓ IDE config generated for VS Code + Zed", tone: "success" },
			{ text: "✓ Ports allocated: web :4200 · api :4201 · postgres :4210", tone: "success" },
			{ text: "✓ Stackpanel agent listening on http://localhost:9876", tone: "success" },
			{ text: "" },
			{ text: "STACKPANEL_PROJECT=myapp", tone: "muted" },
			{ text: "STACKPANEL_POSTGRES_PORT=4210", tone: "muted" },
			{ text: "Welcome back, charles. Type `dev` to start.", tone: "highlight" },
		],
	},
	{
		id: "services",
		label: "Run the stack",
		prompt: "(myapp) $",
		command: "dev",
		lines: [
			{ text: "→ process-compose: starting myapp", tone: "info" },
			{ text: "✓ step-ca       READY     internal CA + ACME", tone: "success" },
			{ text: "✓ caddy         READY     https://*.myapp.local", tone: "success" },
			{ text: "✓ postgres      READY     :4210", tone: "success" },
			{ text: "✓ redis         READY     :4211", tone: "success" },
			{ text: "✓ minio         READY     :4212  console :4213", tone: "success" },
			{ text: "✓ web           READY     https://web.myapp.local", tone: "success" },
			{ text: "✓ api           READY     https://api.myapp.local", tone: "success" },
			{ text: "" },
			{ text: "→ Studio: https://studio.myapp.local", tone: "highlight" },
		],
	},
	{
		id: "secrets",
		label: "Add a secret",
		prompt: "(myapp) $",
		command: "stackpanel secrets edit dev",
		lines: [
			{ text: "→ Decrypting .stack/secrets/dev.sops.yaml with local AGE key", tone: "info" },
			{ text: "→ Opening $EDITOR…", tone: "muted" },
			{ text: "+ STRIPE_SECRET_KEY: sk_test_…", tone: "success" },
			{ text: "✓ Re-encrypted for 4 recipients", tone: "success" },
			{ text: "✓ Regenerated @gen/env/api with new field", tone: "success" },
			{ text: "" },
			{ text: "Next:", tone: "muted" },
			{ text: "  git add .stack/secrets/dev.sops.yaml packages/gen/env", tone: "muted" },
			{ text: "  git commit -m 'feat: stripe secret'", tone: "muted" },
		],
	},
];

const toneClasses: Record<NonNullable<TerminalLine["tone"]>, string> = {
	info: "text-muted-foreground",
	success: "text-accent",
	warning: "text-yellow-400",
	muted: "text-muted-foreground/80",
	highlight: "font-semibold text-accent",
};

export function TerminalSection() {
	const [activeTab, setActiveTab] = useState(tabs[0].id);
	const current = tabs.find((tab) => tab.id === activeTab) ?? tabs[0];

	return (
		<section className="border-border border-b bg-secondary/20" id="cli">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="text-center">
					<p className="font-medium text-accent text-sm">CLI</p>
					<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
						Real commands, no proprietary glue
					</h2>
					<p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
						The{" "}
						<span className="font-mono text-foreground">stackpanel</span> CLI
						speaks Nix, SOPS, and process-compose. Every command operates on
						standard files in your repo.
					</p>
				</div>

				<div className="mx-auto mt-12 max-w-4xl">
					<div className="overflow-hidden rounded-xl border border-border bg-card shadow-2xl">
						<div className="flex items-center justify-between border-border border-b bg-secondary/50 px-2 sm:px-4">
							<div className="flex overflow-x-auto">
								{tabs.map((tab) => (
									<button
										className={cn(
											"shrink-0 border-b-2 px-3 py-3 font-medium text-sm transition-colors sm:px-4",
											activeTab === tab.id
												? "border-accent text-foreground"
												: "border-transparent text-muted-foreground hover:text-foreground",
										)}
										key={tab.id}
										onClick={() => setActiveTab(tab.id)}
										type="button"
									>
										{tab.label}
									</button>
								))}
							</div>
							<div className="hidden gap-1.5 pr-2 sm:flex">
								<div className="h-3 w-3 rounded-full bg-red-500/80" />
								<div className="h-3 w-3 rounded-full bg-yellow-500/80" />
								<div className="h-3 w-3 rounded-full bg-green-500/80" />
							</div>
						</div>

						<div className="overflow-x-auto p-4 font-mono text-sm sm:p-6">
							<div className="flex items-start gap-2">
								<span className="text-muted-foreground">{current.prompt}</span>
								<span className="break-all text-foreground">
									{current.command}
								</span>
							</div>
							<div className="mt-4 space-y-1">
								{current.lines.map((line, i) => (
									<div
										className={cn(
											line.text === "" && "h-4",
											line.tone ? toneClasses[line.tone] : "text-foreground",
										)}
										key={`${current.id}-line-${i}`}
									>
										{line.text}
									</div>
								))}
							</div>
						</div>
					</div>

					<p className="mt-4 text-center text-muted-foreground text-xs">
						Same command works on macOS, Linux, and NixOS — same versions, same
						output.
					</p>
				</div>
			</div>
		</section>
	);
}
