import { Link } from "@tanstack/react-router";
import { Button } from "@ui/button";
import {
	ArrowRight,
	Cloud,
	Database,
	HardDrive,
	Lock,
	Network,
	Radio,
	ShieldCheck,
	Workflow,
} from "lucide-react";

type Service = {
	icon: typeof Database;
	name: string;
	description: string;
	envVar: string;
	tag: string;
};

const coreServices: Service[] = [
	{
		icon: Database,
		name: "PostgreSQL",
		description: "Local cluster with persistent data dir, ready for migrations.",
		envVar: "STACKPANEL_POSTGRES_PORT",
		tag: "global",
	},
	{
		icon: Radio,
		name: "Redis",
		description: "Single-node cache for sessions, queues, and rate limits.",
		envVar: "STACKPANEL_REDIS_PORT",
		tag: "global",
	},
	{
		icon: HardDrive,
		name: "MinIO",
		description: "S3-compatible object storage with admin console exposed.",
		envVar: "STACKPANEL_MINIO_PORT",
		tag: "global",
	},
	{
		icon: Network,
		name: "Caddy",
		description: "Reverse proxy that wires *.local hostnames to your apps.",
		envVar: "STACKPANEL_CADDY_PORT",
		tag: "network",
	},
	{
		icon: ShieldCheck,
		name: "Step CA",
		description: "Internal certificate authority — real HTTPS in dev, no warnings.",
		envVar: "STACKPANEL_STEP_CA_PORT",
		tag: "network",
	},
	{
		icon: Workflow,
		name: "process-compose",
		description: "Health probes, dependencies, and restart policies for everything above.",
		envVar: "STACKPANEL_PC_PORT",
		tag: "orchestrator",
	},
];

const tagStyles: Record<string, string> = {
	global: "border-emerald-500/30 bg-emerald-500/10 text-emerald-300",
	network: "border-sky-500/30 bg-sky-500/10 text-sky-300",
	orchestrator: "border-purple-500/30 bg-purple-500/10 text-purple-300",
};

export function InfrastructureSection() {
	return (
		<section
			className="border-border border-b bg-secondary/20"
			id="infrastructure"
		>
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="grid gap-12 lg:grid-cols-[5fr_7fr] lg:gap-16">
					<div className="flex flex-col">
						<p className="font-medium text-accent text-sm">
							Local infrastructure
						</p>
						<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
							Production-shaped services on your laptop.
						</h2>
						<p className="mt-4 text-pretty text-muted-foreground leading-relaxed">
							Stackpanel runs the same data stores you use in production —
							Postgres, Redis, MinIO — orchestrated by{" "}
							<span className="font-mono text-foreground">process-compose</span>{" "}
							with health probes and dependency ordering.
						</p>
						<p className="mt-4 text-pretty text-muted-foreground leading-relaxed">
							Caddy and an internal Step CA give you real HTTPS at clean
							hostnames like{" "}
							<span className="font-mono text-foreground">
								https://api.myapp.local
							</span>{" "}
							— so OAuth, secure cookies, and webhooks behave like prod.
						</p>

						<div className="mt-8 flex flex-wrap gap-3">
							<Button
								asChild
								className="bg-foreground text-background hover:bg-foreground/90"
							>
								<Link to="/studio">
									Open the Studio
									<ArrowRight className="ml-2 h-4 w-4" />
								</Link>
							</Button>
							<Button asChild variant="outline">
								<a
									href="https://github.com/darkmatter/stackpanel"
									rel="noopener noreferrer"
									target="_blank"
								>
									Read the docs
								</a>
							</Button>
						</div>

						<div className="mt-10 rounded-xl border border-border bg-background/60 p-5">
							<div className="flex items-center gap-2">
								<Cloud className="h-4 w-4 text-accent" />
								<span className="font-semibold text-foreground text-sm">
									Same shape, your cloud
								</span>
							</div>
							<p className="mt-2 text-muted-foreground text-sm leading-relaxed">
								Modules can target NixOS or container runtimes for staging and
								production. Same config language, same generated Caddyfile,
								same SOPS recipients — different host.
							</p>
						</div>
					</div>

					<div className="grid gap-px overflow-hidden rounded-2xl border border-border bg-border sm:grid-cols-2">
						{coreServices.map((service) => (
							<div
								className="group flex flex-col gap-3 bg-card p-5 transition-colors hover:bg-card/80"
								key={service.name}
							>
								<div className="flex items-start justify-between gap-3">
									<div className="flex h-11 w-11 items-center justify-center rounded-lg bg-secondary transition-colors group-hover:bg-accent/20">
										<service.icon className="h-5 w-5 text-muted-foreground transition-colors group-hover:text-accent" />
									</div>
									<span
										className={`rounded-full border px-2 py-0.5 font-mono text-[10px] tracking-[0.04em] ${tagStyles[service.tag]}`}
									>
										{service.tag}
									</span>
								</div>
								<div>
									<p className="font-semibold text-foreground text-base">
										{service.name}
									</p>
									<p className="mt-1 text-muted-foreground text-xs leading-relaxed">
										{service.description}
									</p>
								</div>
								<div className="mt-auto flex items-center gap-2 border-border/60 border-t pt-3 font-mono text-[11px]">
									<Lock className="h-3 w-3 text-muted-foreground" />
									<span className="text-muted-foreground">
										{service.envVar}
									</span>
								</div>
							</div>
						))}
					</div>
				</div>
			</div>
		</section>
	);
}
