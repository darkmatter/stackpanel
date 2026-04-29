import {
	ArrowDownToLine,
	Check,
	Globe,
	KeyRound,
	Sparkles,
	TerminalSquare,
} from "lucide-react";

const pillars = [
	{
		icon: ArrowDownToLine,
		title: "Onboarding without docs",
		description:
			"git clone, direnv allow, done. Devshell installs every runtime, generates IDE settings, drops scripts on $PATH, and opens the studio.",
		stat: "≈ 2 commands",
	},
	{
		icon: Globe,
		title: "Real URLs, real ports",
		description:
			"Hit https://web.myapp.local in any browser. OAuth callbacks, secure cookies, and webhooks behave the same as in production.",
		stat: "TLS in dev",
	},
	{
		icon: KeyRound,
		title: "Secrets that just work",
		description:
			"Add a teammate's AGE key, rekey the SOPS files, commit the diff. Their next direnv reload pulls the new keys with zero config.",
		stat: "SOPS · AGE",
	},
	{
		icon: TerminalSquare,
		title: "Project commands on $PATH",
		description:
			"Declared scripts (dev, lint, test, deploy) become real binaries. Every teammate runs the same command — no per-shell aliases.",
		stat: "scripts.* in Nix",
	},
];

const onboardingSteps = [
	{ command: "git clone …", detail: "Pull the repo as usual" },
	{ command: "direnv allow", detail: "Devshell builds in the background" },
	{ command: "dev", detail: "Apps + services come up; studio opens" },
];

export function DevExperienceSection() {
	return (
		<section className="border-border border-b" id="devex">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="grid gap-12 lg:grid-cols-[5fr_7fr] lg:gap-16">
					<div className="flex flex-col">
						<p className="font-medium text-accent text-sm">
							Developer experience
						</p>
						<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
							Onboarding measured in minutes, not days.
						</h2>
						<p className="mt-4 text-pretty text-muted-foreground leading-relaxed">
							The README on most repos starts with a 14-step setup guide.
							Stackpanel replaces it with{" "}
							<span className="font-mono text-foreground">direnv allow</span>{" "}
							— and a teammate is running the full stack on the same ports as
							everyone else.
						</p>

						<div className="mt-8 overflow-hidden rounded-xl border border-border bg-background">
							<div className="flex items-center gap-2 border-border border-b bg-secondary/40 px-4 py-2.5">
								<Sparkles className="h-3.5 w-3.5 text-accent" />
								<span className="font-mono text-muted-foreground text-xs">
									New hire, day one
								</span>
							</div>
							<ol className="divide-y divide-border/60">
								{onboardingSteps.map((step, idx) => (
									<li
										className="flex items-center gap-4 px-4 py-3"
										key={step.command}
									>
										<span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-border bg-secondary font-mono text-[11px] text-muted-foreground">
											{idx + 1}
										</span>
										<div className="min-w-0 flex-1">
											<p className="truncate font-mono text-foreground text-sm">
												$ {step.command}
											</p>
											<p className="mt-0.5 text-muted-foreground text-xs">
												{step.detail}
											</p>
										</div>
										<Check className="h-4 w-4 text-accent" />
									</li>
								))}
							</ol>
						</div>
					</div>

					<div className="grid gap-px overflow-hidden rounded-2xl border border-border bg-border sm:grid-cols-2">
						{pillars.map((pillar) => (
							<div
								className="flex flex-col gap-3 bg-card p-6 transition-colors hover:bg-card/80"
								key={pillar.title}
							>
								<div className="flex items-start justify-between gap-3">
									<div className="flex h-11 w-11 items-center justify-center rounded-lg bg-accent/10">
										<pillar.icon className="h-5 w-5 text-accent" />
									</div>
									<span className="rounded-full border border-border bg-background/60 px-2 py-0.5 font-mono text-[10px] text-muted-foreground tracking-[0.04em]">
										{pillar.stat}
									</span>
								</div>
								<h3 className="font-semibold text-foreground text-lg">
									{pillar.title}
								</h3>
								<p className="text-muted-foreground text-sm leading-relaxed">
									{pillar.description}
								</p>
							</div>
						))}
					</div>
				</div>
			</div>
		</section>
	);
}
