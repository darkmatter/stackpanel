import {
	ArrowRight,
	Box,
	Cpu,
	FileTerminal,
	GitBranch,
	MonitorPlay,
	Radio,
} from "lucide-react";

const planes = [
	{
		id: "nix",
		number: "01",
		icon: FileTerminal,
		title: "Nix plane",
		tagline: "Declarative source of truth",
		description:
			"Evaluates your config, computes ports from your project name, provisions the devshell, and generates files. Runs once on shell entry.",
		highlights: [
			"flake-parts + devenv adapter",
			"Per-app code generation",
			"SOPS recipients in Nix config",
		],
	},
	{
		id: "agent",
		number: "02",
		icon: Cpu,
		title: "Local agent",
		tagline: "Bridge to your environment",
		description:
			"A Go binary on localhost:9876 that wraps Nix evaluation, manages services via process-compose, watches files, and serves the studio.",
		highlights: [
			"REST + Connect-RPC + SSE",
			"JWT pairing flow",
			"Works fully offline",
		],
	},
	{
		id: "studio",
		number: "03",
		icon: MonitorPlay,
		title: "Web studio",
		tagline: "Manage everything visually",
		description:
			"A React app for browsing extensions, managing services, editing config, viewing generated files, and resolving secrets — without writing Nix.",
		highlights: [
			"Real-time SSE updates",
			"Form-based config editor",
			"Per-extension panels",
		],
	},
];

export function HowItWorksSection() {
	return (
		<section className="relative border-border border-b" id="how-it-works">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="text-center">
					<p className="font-medium text-accent text-sm">
						How it works
					</p>
					<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
						Three planes, one project
					</h2>
					<p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
						Stackpanel runs as a Nix configuration, a local Go agent, and a web
						studio. Each plane has a clear job — together they replace the
						boilerplate that lives between your code and production.
					</p>
				</div>

				<div className="relative mt-16">
					<div
						aria-hidden
						className="absolute inset-x-0 top-1/2 hidden h-px bg-gradient-to-r from-transparent via-border to-transparent lg:block"
					/>
					<div className="grid gap-6 lg:grid-cols-3 lg:gap-8">
						{planes.map((plane, index) => (
							<div
								className="group relative flex flex-col rounded-2xl border border-border bg-card p-6 transition-colors hover:border-accent/40 hover:bg-card/80"
								key={plane.id}
							>
								<div className="flex items-center justify-between">
									<div className="flex items-center gap-3">
										<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10 text-accent">
											<plane.icon className="h-5 w-5" />
										</div>
										<div>
											<p className="font-mono text-muted-foreground text-xs tracking-[0.2em]">
												{plane.number}
											</p>
											<h3 className="font-semibold text-foreground text-lg">
												{plane.title}
											</h3>
										</div>
									</div>
									{index < planes.length - 1 && (
										<ArrowRight className="hidden h-5 w-5 text-muted-foreground/40 lg:block" />
									)}
								</div>
								<p className="mt-4 font-medium text-accent/90 text-sm">
									{plane.tagline}
								</p>
								<p className="mt-2 flex-1 text-muted-foreground text-sm leading-relaxed">
									{plane.description}
								</p>
								<ul className="mt-5 space-y-2 border-border/60 border-t pt-4 text-foreground/80 text-sm">
									{plane.highlights.map((highlight) => (
										<li
											className="flex items-center gap-2"
											key={highlight}
										>
											<span className="h-1.5 w-1.5 rounded-full bg-accent" />
											{highlight}
										</li>
									))}
								</ul>
							</div>
						))}
					</div>
				</div>

				<div className="mt-12 rounded-2xl border border-border bg-secondary/30 p-6">
					<div className="grid gap-6 lg:grid-cols-3 lg:gap-8">
						<div className="flex items-start gap-3">
							<div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-background text-accent">
								<GitBranch className="h-4 w-4" />
							</div>
							<div>
								<p className="font-semibold text-foreground text-sm">
									Git is the deploy target
								</p>
								<p className="mt-1 text-muted-foreground text-sm">
									Studio writes to your real config files. Diffs show up in
									code review like any other change.
								</p>
							</div>
						</div>
						<div className="flex items-start gap-3">
							<div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-background text-accent">
								<Radio className="h-4 w-4" />
							</div>
							<div>
								<p className="font-semibold text-foreground text-sm">
									Real-time, locally
								</p>
								<p className="mt-1 text-muted-foreground text-sm">
									SSE streams config and service updates from the agent — no
									polling, no cloud round-trips.
								</p>
							</div>
						</div>
						<div className="flex items-start gap-3">
							<div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-background text-accent">
								<Box className="h-4 w-4" />
							</div>
							<div>
								<p className="font-semibold text-foreground text-sm">
									Eject without migration
								</p>
								<p className="mt-1 text-muted-foreground text-sm">
									Generated files live in standard locations. Stop using
									Stackpanel and your repo keeps working.
								</p>
							</div>
						</div>
					</div>
				</div>
			</div>
		</section>
	);
}
