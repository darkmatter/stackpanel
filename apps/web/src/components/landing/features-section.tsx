import {
	Boxes,
	Code2,
	GitBranch,
	Hash,
	KeyRound,
	Layers,
	LockKeyhole,
	Network,
	Package,
	Puzzle,
	Server,
	ShieldCheck,
} from "lucide-react";

const features = [
	{
		icon: Boxes,
		title: "Reproducible devshells",
		description:
			"flake.lock pins every package, runtime, and version. Every teammate gets the exact same Node, Bun, Go, Postgres — independent of their OS.",
		tag: "Nix · devenv",
	},
	{
		icon: Hash,
		title: "Deterministic ports",
		description:
			"Ports are hashed from your project name, then sequenced for apps and services. Same ports on every machine, no .env coordination, no clashes between projects.",
		tag: "STACKPANEL_*_PORT",
	},
	{
		icon: Server,
		title: "Service orchestration",
		description:
			"Postgres, Redis, Minio, Caddy, and Step CA managed by process-compose. One command to start the whole stack with health probes wired up.",
		tag: "process-compose",
	},
	{
		icon: KeyRound,
		title: "Encrypted secrets",
		description:
			"SOPS-encrypted YAML with AGE recipients declared in Nix. Add a teammate's public key, run rekey, commit the diff. No external KMS to manage.",
		tag: "SOPS · AGE",
	},
	{
		icon: ShieldCheck,
		title: "Real HTTPS in dev",
		description:
			"Step CA issues internal certificates and Caddy reverse-proxies your apps to https://*.local — no browser warnings, no self-signed cert wrangling.",
		tag: "Step CA · Caddy",
	},
	{
		icon: Code2,
		title: "IDE auto-config",
		description:
			"VS Code and Zed workspace settings, recommended extensions, and devshell loaders are generated and committed. New hires open the repo and the editor is ready.",
		tag: ".vscode · .zed",
	},
	{
		icon: Package,
		title: "Type-safe @gen/env",
		description:
			"Per-app codegen turns your secret schemas into typed TypeScript modules with embedded encrypted payloads. Import from @gen/env/<app> and ship.",
		tag: "TS · Go · Python",
	},
	{
		icon: Puzzle,
		title: "Extension registry",
		description:
			"Browse extensions in the studio and enable them with one click. Stackpanel writes the Nix config for you and contributes generated files, scripts, and panels.",
		tag: "One-click install",
	},
	{
		icon: GitBranch,
		title: "No vendor lock-in",
		description:
			"Generated files are standard config in standard locations. Stop using Stackpanel and the repo keeps working — there is nothing to migrate.",
		tag: "Eject anytime",
	},
];

export function FeaturesSection() {
	return (
		<section className="border-border border-b" id="features">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="text-center">
					<p className="font-medium text-accent text-sm">Platform</p>
					<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
						Everything that lives between code and production
					</h2>
					<p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
						Stackpanel collapses the dozens of files, services, and
						integrations every team rebuilds from scratch into a single
						declarative configuration.
					</p>
				</div>

				<div className="mt-16 grid gap-px overflow-hidden rounded-2xl border border-border bg-border sm:grid-cols-2 lg:grid-cols-3">
					{features.map((feature) => (
						<div
							className="group relative flex flex-col bg-card p-6 transition-colors hover:bg-card/80"
							key={feature.title}
						>
							<div className="flex items-center justify-between">
								<div className="flex h-11 w-11 items-center justify-center rounded-lg bg-accent/10 text-accent transition-colors group-hover:bg-accent/15">
									<feature.icon className="h-5 w-5" />
								</div>
								<span className="rounded-full border border-border bg-background/60 px-2 py-0.5 font-mono text-[10px] text-muted-foreground tracking-[0.04em]">
									{feature.tag}
								</span>
							</div>
							<h3 className="mt-4 font-semibold text-foreground text-lg">
								{feature.title}
							</h3>
							<p className="mt-2 text-muted-foreground text-sm leading-relaxed">
								{feature.description}
							</p>
						</div>
					))}
				</div>

				<div className="mt-10 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-muted-foreground text-xs">
					<span className="inline-flex items-center gap-1.5">
						<LockKeyhole className="h-3.5 w-3.5" />
						No data leaves your machine in dev
					</span>
					<span className="inline-flex items-center gap-1.5">
						<Layers className="h-3.5 w-3.5" />
						Composes with devenv, flake-parts, and SST
					</span>
					<span className="inline-flex items-center gap-1.5">
						<Network className="h-3.5 w-3.5" />
						Local-first · works offline
					</span>
				</div>
			</div>
		</section>
	);
}
