import { ArrowRight, FileCode2, FolderTree } from "lucide-react";

const configLines: Array<{
	text: string;
	tone?: "muted" | "comment" | "key" | "string" | "value" | "punct";
}> = [
	{ text: "{ pkgs, ... }: {", tone: "punct" },
	{ text: "  stackpanel = {", tone: "key" },
	{ text: "    enable = true;", tone: "value" },
	{ text: '    name   = "myapp";', tone: "value" },
	{ text: "" },
	{ text: "    # Apps get sequential ports from the hashed base", tone: "comment" },
	{ text: "    apps = {", tone: "key" },
	{ text: "      web = { port = 0; };  # → :4200", tone: "value" },
	{ text: "      api = { port = 1; };  # → :4201", tone: "value" },
	{ text: "    };", tone: "punct" },
	{ text: "" },
	{ text: "    # Background services managed by process-compose", tone: "comment" },
	{ text: "    globalServices = {", tone: "key" },
	{ text: "      enable = true;", tone: "value" },
	{ text: "      postgres.enable = true;", tone: "value" },
	{ text: "      redis.enable    = true;", tone: "value" },
	{ text: "      minio.enable    = true;", tone: "value" },
	{ text: "    };", tone: "punct" },
	{ text: "" },
	{ text: "    # Real HTTPS for *.myapp.local", tone: "comment" },
	{ text: "    caddy.enable     = true;", tone: "value" },
	{ text: "    step-ca.enable   = true;", tone: "value" },
	{ text: "" },
	{ text: "    # Editor settings + extensions, generated for the team", tone: "comment" },
	{ text: "    ide = {", tone: "key" },
	{ text: "      enable        = true;", tone: "value" },
	{ text: "      vscode.enable = true;", tone: "value" },
	{ text: "      zed.enable    = true;", tone: "value" },
	{ text: "    };", tone: "punct" },
	{ text: "" },
	{ text: "    # SOPS recipients live in Nix", tone: "comment" },
	{ text: "    secrets.recipients = config.stackpanel.users.allKeys;", tone: "value" },
	{ text: "" },
	{ text: "    # Project commands available on $PATH", tone: "comment" },
	{ text: "    scripts.dev = {", tone: "key" },
	{ text: '      exec        = "bun run --filter \'./apps/*\' dev";', tone: "value" },
	{ text: '      description = "Start every app in dev mode";', tone: "value" },
	{ text: "    };", tone: "punct" },
	{ text: "  };", tone: "punct" },
	{ text: "}", tone: "punct" },
];

const toneClasses: Record<NonNullable<(typeof configLines)[number]["tone"]>, string> = {
	muted: "text-muted-foreground",
	comment: "text-muted-foreground/70 italic",
	key: "text-foreground",
	string: "text-emerald-300",
	value: "text-foreground/90",
	punct: "text-muted-foreground",
};

const generated: Array<{
	path: string;
	description: string;
}> = [
	{
		path: ".vscode/settings.json",
		description: "Workspace settings + recommended extensions for VS Code",
	},
	{
		path: ".zed/settings.json",
		description: "Language server config + Nix integration for Zed",
	},
	{
		path: ".stack/secrets/.sops.yaml",
		description: "SOPS creation rules rendered from declared recipients",
	},
	{
		path: "packages/gen/env/src/<app>.ts",
		description: "Type-safe env modules per app with embedded payloads",
	},
	{
		path: ".stack/state/stack.json",
		description: "Resolved ports, URLs, services for the Go agent",
	},
	{
		path: ".stack/gen/process-compose.yaml",
		description: "Service definitions with health probes and dependencies",
	},
	{
		path: ".vscode/launch.json",
		description: "Debug configurations contributed by app modules",
	},
	{
		path: "Caddyfile",
		description: "Reverse-proxy routes for *.local hostnames with TLS",
	},
];

export function ConfigShowcaseSection() {
	return (
		<section className="border-border border-b bg-secondary/20" id="config">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="grid gap-12 lg:grid-cols-[5fr_4fr] lg:gap-16">
					<div className="flex flex-col">
						<p className="font-medium text-accent text-sm">
							One config, everything generated
						</p>
						<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
							Declare your stack once.
						</h2>
						<p className="mt-4 text-pretty text-muted-foreground leading-relaxed">
							A single{" "}
							<span className="font-mono text-foreground">.stack/config.nix</span>{" "}
							describes your apps, services, secrets, ports, IDE settings, and
							deployment. Everything else — the dotfiles, the Caddyfile, the
							SOPS rules, the type-safe env modules — is build output.
						</p>

						<div className="mt-6 overflow-hidden rounded-xl border border-border bg-background shadow-2xl">
							<div className="flex items-center justify-between border-border border-b bg-secondary/40 px-4 py-2.5">
								<div className="flex items-center gap-2 text-muted-foreground text-xs">
									<FileCode2 className="h-3.5 w-3.5" />
									<span className="font-mono">.stack/config.nix</span>
								</div>
								<div className="flex gap-1.5">
									<span className="h-2.5 w-2.5 rounded-full bg-red-500/70" />
									<span className="h-2.5 w-2.5 rounded-full bg-yellow-500/70" />
									<span className="h-2.5 w-2.5 rounded-full bg-green-500/70" />
								</div>
							</div>
							<div className="overflow-x-auto p-4 font-mono text-[13px] leading-relaxed">
								<pre className="min-w-max">
									{configLines.map((line, idx) => (
										<div
											className={
												line.tone ? toneClasses[line.tone] : "text-foreground"
											}
											key={`config-line-${idx}`}
										>
											{line.text || "\u00A0"}
										</div>
									))}
								</pre>
							</div>
						</div>

						<p className="mt-4 text-muted-foreground text-xs">
							Don&apos;t want to write Nix? Open the studio — every option has a
							form, and changes are written back to this file.
						</p>
					</div>

					<div className="flex flex-col">
						<div className="flex items-center gap-2 font-medium text-accent text-sm">
							<ArrowRight className="h-4 w-4" />
							Builds into
						</div>
						<h3 className="mt-3 font-semibold font-[Montserrat] text-2xl text-foreground sm:text-3xl">
							The dotfiles you would have written by hand.
						</h3>
						<p className="mt-3 text-muted-foreground text-sm leading-relaxed">
							Generated files live where every tool expects them, in formats
							every teammate already knows. Studio shows you which files are
							stale, which module wrote them, and what would change if you
							regenerated.
						</p>

						<div className="mt-6 rounded-xl border border-border bg-background">
							<div className="flex items-center gap-2 border-border border-b px-4 py-2.5 text-muted-foreground text-xs">
								<FolderTree className="h-3.5 w-3.5" />
								<span className="font-mono">Generated by Stackpanel</span>
								<span className="ml-auto rounded-full bg-secondary px-2 py-0.5 text-[10px]">
									{generated.length} files
								</span>
							</div>
							<ul className="divide-y divide-border/60">
								{generated.map((file) => (
									<li
										className="flex items-start gap-3 px-4 py-3 transition-colors hover:bg-secondary/40"
										key={file.path}
									>
										<span className="mt-0.5 inline-block h-2 w-2 shrink-0 rounded-full bg-accent" />
										<div className="min-w-0 flex-1">
											<p className="truncate font-mono text-foreground text-sm">
												{file.path}
											</p>
											<p className="mt-0.5 text-muted-foreground text-xs">
												{file.description}
											</p>
										</div>
									</li>
								))}
							</ul>
						</div>
					</div>
				</div>
			</div>
		</section>
	);
}
