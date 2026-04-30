import { Button } from "@ui/button";
import {
	CheckCircle2,
	Cloud,
	Globe2,
	HardDrive,
	type LucideIcon,
	Network,
	Server,
	Workflow,
} from "lucide-react";

type Stack = {
	id: string;
	name: string;
	tagline: string;
	icon: LucideIcon;
	targets: string[];
	bullets: string[];
	example: { line: string; tone?: "comment" | "value" | "punct" }[];
	docHref: string;
};

const stacks: Stack[] = [
	{
		id: "alchemy",
		name: "Alchemy",
		tagline:
			"Resource-graph IaC for the full TypeScript stack — Cloudflare, AWS, Vercel.",
		icon: Workflow,
		targets: ["Cloudflare", "AWS", "Vercel", "GitHub", "Stripe"],
		bullets: [
			"Type-safe bindings generated into your app",
			"Per-PR preview environments out of the box",
			"Secrets pulled straight from .stack/secrets",
			"State stored in your repo or your S3 bucket",
		],
		example: [
			{ line: "# .stack/config.nix", tone: "comment" },
			{ line: "apps.web = {", tone: "punct" },
			{ line: '  framework = "nextjs";', tone: "value" },
			{ line: "  alchemy = {", tone: "punct" },
			{ line: '    target = "cloudflare";  # or "aws" | "vercel"', tone: "value" },
			{ line: "    previews = true;", tone: "value" },
			{ line: "  };", tone: "punct" },
			{ line: "};", tone: "punct" },
		],
		docHref: "/docs/stacks/alchemy",
	},
	{
		id: "colmena",
		name: "Colmena",
		tagline:
			"NixOS deploys for the people who want full control — Hetzner, bare metal, your own racks.",
		icon: Server,
		targets: ["Hetzner CAX/CCX", "Bare metal", "Any NixOS host", "Tailscale"],
		bullets: [
			"Atomic switch with one-command rollback",
			"Machine groups for canary + production fleets",
			"Secrets via agenix, recipients managed in Nix",
			"Caddy + Step CA wired identically to dev",
		],
		example: [
			{ line: "# .stack/config.nix", tone: "comment" },
			{ line: "apps.api = {", tone: "punct" },
			{ line: "  colmena = {", tone: "punct" },
			{ line: '    host    = "cax21.fra";', tone: "value" },
			{ line: "    replicas = 2;", tone: "value" },
			{ line: "    rollback.enable = true;", tone: "value" },
			{ line: "  };", tone: "punct" },
			{ line: "};", tone: "punct" },
		],
		docHref: "/docs/stacks/colmena",
	},
	{
		id: "fly",
		name: "Fly.io",
		tagline:
			"Containerized apps at the edge — regional placement, Fly volumes, Fly Postgres.",
		icon: Globe2,
		targets: ["Fly Machines", "Fly Postgres", "Fly Volumes", "Tigris (S3)"],
		bullets: [
			"Multi-region machines from one Nix config",
			"Health probes, autoscale, and graceful drain",
			"Fly secrets sync from .stack/secrets at deploy",
			"Built-in observability via Fly Metrics",
		],
		example: [
			{ line: "# .stack/config.nix", tone: "comment" },
			{ line: "apps.api.fly = {", tone: "punct" },
			{ line: '  regions  = [ "iad" "fra" "sin" ];', tone: "value" },
			{ line: "  machines = 3;", tone: "value" },
			{ line: '  postgres.cluster = "myapp-pg";', tone: "value" },
			{ line: "  autoscale.maxMachines = 10;", tone: "value" },
			{ line: "};", tone: "punct" },
		],
		docHref: "/docs/stacks/fly",
	},
];

const toneClasses: Record<string, string> = {
	comment: "text-muted-foreground/70 italic",
	value: "text-foreground/90",
	punct: "text-muted-foreground",
};

const promiseBullets: { icon: LucideIcon; text: string }[] = [
	{
		icon: CheckCircle2,
		text: "Same-day patches when nixpkgs ships breaking updates",
	},
	{
		icon: CheckCircle2,
		text: "Tested against every flake.lock bump before release",
	},
	{
		icon: CheckCircle2,
		text: "Provider API drift handled before it breaks your deploys",
	},
];

export function ProductionStacksSection() {
	return (
		<section
			className="border-border border-b bg-secondary/10"
			id="stacks"
		>
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="text-center">
					<p className="font-medium text-accent text-sm">
						Production stacks
					</p>
					<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
						Deploy without becoming a platform team.
					</h2>
					<p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
						Production Stacks are maintained Nix flake inputs that take your
						app from{" "}
						<span className="font-mono text-foreground">.stack/config.nix</span>{" "}
						all the way to production. Stick to the conventions and you should
						never need more than one option flip.
					</p>

					<div className="mx-auto mt-6 inline-flex items-center gap-2 rounded-full border border-border bg-background/60 px-4 py-1.5">
						<span className="font-mono text-foreground text-xs">
							apps.&lt;myapp&gt;.nextjs.enable = true;
						</span>
					</div>
				</div>

				<div className="mt-14 grid gap-6 lg:grid-cols-3">
					{stacks.map((stack) => (
						<div
							className="flex flex-col rounded-2xl border border-border bg-card transition-colors hover:border-accent/40"
							key={stack.id}
						>
							<div className="flex items-start justify-between gap-3 p-6 pb-4">
								<div className="flex items-center gap-3">
									<div className="flex h-11 w-11 items-center justify-center rounded-lg bg-accent/10 text-accent">
										<stack.icon className="h-5 w-5" />
									</div>
									<div>
										<h3 className="font-semibold text-foreground text-lg">
											{stack.name}
										</h3>
										<p className="text-muted-foreground text-xs">
											Stable · maintained
										</p>
									</div>
								</div>
							</div>

							<p className="px-6 pb-4 text-muted-foreground text-sm leading-relaxed">
								{stack.tagline}
							</p>

							<div className="px-6 pb-4">
								<div className="flex flex-wrap gap-1.5">
									{stack.targets.map((target) => (
										<span
											className="rounded-full border border-border bg-secondary/50 px-2 py-0.5 font-mono text-[11px] text-muted-foreground"
											key={target}
										>
											{target}
										</span>
									))}
								</div>
							</div>

							<div className="mx-6 mb-4 overflow-hidden rounded-lg border border-border/60 bg-background/60 font-mono text-[12px]">
								<div className="border-border/60 border-b bg-secondary/30 px-3 py-1.5 text-[10px] text-muted-foreground tracking-[0.06em] uppercase">
									Example
								</div>
								<pre className="overflow-x-auto p-3 leading-relaxed">
									{stack.example.map((row, i) => (
										<div
											className={
												row.tone
													? toneClasses[row.tone]
													: "text-foreground"
											}
											key={`${stack.id}-line-${i}`}
										>
											{row.line || "\u00A0"}
										</div>
									))}
								</pre>
							</div>

							<ul className="mt-auto flex flex-col gap-2 border-border/60 border-t px-6 py-4">
								{stack.bullets.map((bullet) => (
									<li
										className="flex items-start gap-2 text-muted-foreground text-xs"
										key={bullet}
									>
										<CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-accent" />
										<span className="leading-relaxed">{bullet}</span>
									</li>
								))}
							</ul>
						</div>
					))}
				</div>

				<div className="mt-12 grid gap-8 rounded-2xl border border-border bg-card p-6 sm:p-8 lg:grid-cols-[2fr_3fr] lg:gap-12">
					<div>
						<div className="inline-flex items-center gap-2 rounded-full border border-accent/30 bg-accent/10 px-3 py-1 text-accent text-xs">
							<HardDrive className="h-3.5 w-3.5" />
							Our promise
						</div>
						<h3 className="mt-4 font-semibold font-[Montserrat] text-2xl text-foreground">
							You write the convention. We keep it green.
						</h3>
						<p className="mt-3 text-muted-foreground text-sm leading-relaxed">
							Stacks are versioned Nix flake inputs. Subscribers get the
							private stable channel and a maintenance commitment — same-day
							patches, tested against every nixpkgs and provider API change.
						</p>

						<div className="mt-6 flex flex-wrap gap-3">
							<Button asChild variant="outline">
								<a href="/docs/stacks">Browse all stacks</a>
							</Button>
						</div>
					</div>

					<ul className="grid gap-3 sm:grid-cols-1">
						{promiseBullets.map((item) => (
							<li
								className="flex items-start gap-3 rounded-lg border border-border/60 bg-background/40 p-4"
								key={item.text}
							>
								<item.icon className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
								<p className="text-foreground text-sm leading-relaxed">
									{item.text}
								</p>
							</li>
						))}
						<li className="flex items-start gap-3 rounded-lg border border-border/60 bg-background/40 p-4">
							<Cloud className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
							<div>
								<p className="text-foreground text-sm leading-relaxed">
									Marketplace coming soon
								</p>
								<p className="mt-1 text-muted-foreground text-xs leading-relaxed">
									Third-party creators can ship and sell their own
									Production Stacks — Stackpanel takes 20%, you keep 80%.
								</p>
							</div>
						</li>
					</ul>
				</div>

				<p className="mt-8 inline-flex items-center gap-2 text-muted-foreground text-xs">
					<Network className="h-3.5 w-3.5" />
					Solo developers always have free access to the community branch of
					every stack.
				</p>
			</div>
		</section>
	);
}
