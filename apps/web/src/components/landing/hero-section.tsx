import { Link } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { useWaitlist } from "./waitlist-dialog";
import {
	ArrowRight,
	Boxes,
	CheckCircle2,
	Database,
	FileCode2,
	Globe2,
	KeyRound,
	Layers,
	Network,
	Play,
	Server,
	Square,
	Terminal,
} from "lucide-react";
import { type ReactNode, useEffect, useMemo, useState } from "react";
import { cn } from "@/lib/utils";

function Headline() {
	return (
		<h1 className="-mt-4 text-balance font-bold text-4xl text-foreground tracking-tight font-[Montserrat] sm:text-5xl lg:text-6xl">
			<span
				style={{
					fontVariationSettings: '"wght" 210',
					fontWeight: "unset",
					fontFamily: "Montserrat",
					letterSpacing: "-0.15rem",
					lineHeight: "5.4rem",
				}}
			>
				Ship{" "}
			</span>
			<span
				className="font-bold text-accent italic"
				style={{
					fontWeight: "unset",
					fontVariationSettings: '"wght" 807',
					textDecoration: "underline",
					textUnderlineOffset: "5px",
					textDecorationThickness: "from-font",
					letterSpacing: "-0.05rem",
				}}
			>
				products,
			</span>
			<br />
			<span
				className="font-bold text-primary"
				style={{
					fontVariationSettings: '"wght" 420',
					letterSpacing: "0.01rem",
					fontStyle: "normal",
				}}
			>
				not plumbing.
			</span>
		</h1>
	);
}

type AppPreview = {
	id: string;
	name: string;
	stack: string;
	status: "running" | "building" | "stopped";
	domain: string;
	port: number;
};

const APP_PREVIEW: AppPreview[] = [
	{
		id: "web",
		name: "web",
		stack: "TanStack Start · Vite",
		status: "running",
		domain: "web.myapp.local",
		port: 4200,
	},
	{
		id: "api",
		name: "api",
		stack: "Hono · Cloudflare Workers",
		status: "running",
		domain: "api.myapp.local",
		port: 4201,
	},
	{
		id: "worker",
		name: "queue-worker",
		stack: "Go · process-compose",
		status: "building",
		domain: "—",
		port: 4202,
	},
];

type ServicePreview = {
	id: string;
	name: string;
	envVar: string;
	port: number;
	description: string;
};

const SERVICE_PREVIEW: ServicePreview[] = [
	{
		id: "postgres",
		name: "PostgreSQL 16",
		envVar: "STACKPANEL_POSTGRES_PORT",
		port: 4237,
		description: "Hashed from project name · isolated per-project",
	},
	{
		id: "redis",
		name: "Redis 7",
		envVar: "STACKPANEL_REDIS_PORT",
		port: 4252,
		description: "Cache + pub/sub managed by process-compose",
	},
	{
		id: "minio",
		name: "Minio (S3)",
		envVar: "STACKPANEL_MINIO_PORT",
		port: 4263,
		description: "Local object storage with presigned URLs",
	},
	{
		id: "caddy",
		name: "Caddy + Step CA",
		envVar: "STACKPANEL_CADDY_PORT",
		port: 4280,
		description: "Real HTTPS for *.myapp.local in dev",
	},
];

type VariablePreview = {
	id: string;
	key: string;
	kind: "secret" | "config" | "service";
	scope: string;
	masked?: string;
};

const VARIABLE_PREVIEW: VariablePreview[] = [
	{
		id: "DATABASE_URL",
		key: "DATABASE_URL",
		kind: "secret",
		scope: "api · worker",
		masked: "ref+sops://prod.sops.yaml#/DATABASE_URL",
	},
	{
		id: "STACKPANEL_API_PORT",
		key: "STACKPANEL_API_PORT",
		kind: "service",
		scope: "all apps",
		masked: "4201",
	},
	{
		id: "VITE_PUBLIC_API_URL",
		key: "VITE_PUBLIC_API_URL",
		kind: "config",
		scope: "web",
		masked: "https://api.myapp.local",
	},
	{
		id: "AGE_RECIPIENTS",
		key: "AGE_RECIPIENTS",
		kind: "secret",
		scope: "team · 4 keys",
		masked: "age1qd…ek7c, age1n4…tlkq, +2",
	},
];

const STATUS_STYLES: Record<AppPreview["status"], string> = {
	running: "border-emerald-400/40 bg-emerald-500/10 text-emerald-300",
	building: "border-amber-400/40 bg-amber-500/10 text-amber-300",
	stopped: "border-zinc-400/30 bg-zinc-500/10 text-zinc-300",
};

const VARIABLE_STYLES: Record<VariablePreview["kind"], string> = {
	secret:
		"bg-fuchsia-500/10 text-fuchsia-300 border border-fuchsia-400/30",
	config: "bg-sky-500/10 text-sky-300 border border-sky-400/30",
	service: "bg-emerald-500/10 text-emerald-300 border border-emerald-400/30",
};

type PreviewSlide = {
	id: string;
	label: string;
	tagline: string;
	icon: typeof Boxes;
	content: ReactNode;
};

const ROTATION_MS = 6500;

function PreviewFrame({
	title,
	subtitle,
	icon: Icon,
	children,
}: {
	title: string;
	subtitle: string;
	icon: typeof Boxes;
	children: ReactNode;
}) {
	return (
		<div className="flex h-full flex-col gap-4 rounded-xl border border-border/70 bg-card p-5">
			<div className="flex items-center justify-between gap-3">
				<div className="flex items-center gap-3">
					<div className="flex h-9 w-9 items-center justify-center rounded-lg bg-accent/10 text-accent">
						<Icon className="h-4 w-4" />
					</div>
					<div>
						<p className="font-semibold text-foreground text-sm">{title}</p>
						<p className="text-muted-foreground text-xs">{subtitle}</p>
					</div>
				</div>
				<Badge
					className="border-border/70 bg-secondary text-[10px] tracking-[0.12em] uppercase"
					variant="outline"
				>
					Studio
				</Badge>
			</div>
			<div className="min-h-0 flex-1">{children}</div>
		</div>
	);
}

function AppsPreview() {
	return (
		<PreviewFrame
			icon={Boxes}
			subtitle="Deterministic ports · stack-aware tasks · live status"
			title="Apps"
		>
			<div className="grid gap-3">
				{APP_PREVIEW.map((app) => (
					<div
						className="rounded-lg border border-border/70 bg-background/60 p-3"
						key={app.id}
					>
						<div className="flex items-center justify-between gap-3">
							<div className="flex items-center gap-3">
								<div className="flex h-9 w-9 items-center justify-center rounded-md bg-secondary font-mono text-foreground text-xs">
									{app.name.slice(0, 2).toUpperCase()}
								</div>
								<div>
									<p className="font-medium font-mono text-foreground text-sm">
										{app.name}
									</p>
									<p className="text-muted-foreground text-xs">{app.stack}</p>
								</div>
							</div>
							<Badge
								className={cn("text-xs capitalize", STATUS_STYLES[app.status])}
								variant="outline"
							>
								{app.status === "running" ? (
									<Play className="mr-1 h-2.5 w-2.5 fill-current" />
								) : app.status === "building" ? (
									<span className="mr-1 inline-block h-2 w-2 animate-pulse rounded-full bg-current" />
								) : (
									<Square className="mr-1 h-2.5 w-2.5" />
								)}
								{app.status}
							</Badge>
						</div>
						<div className="mt-3 flex flex-wrap items-center gap-2 text-xs">
							<span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5 font-mono text-foreground/80">
								<Globe2 className="h-3 w-3" />
								{app.domain}
							</span>
							<span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5 font-mono text-foreground/80">
								<Network className="h-3 w-3" />:{app.port}
							</span>
						</div>
					</div>
				))}
			</div>
		</PreviewFrame>
	);
}

function ServicesPreview() {
	return (
		<PreviewFrame
			icon={Server}
			subtitle="Postgres · Redis · Minio · Caddy + Step CA"
			title="Services"
		>
			<div className="grid gap-3">
				{SERVICE_PREVIEW.map((svc) => (
					<div
						className="rounded-lg border border-border/70 bg-background/60 p-3"
						key={svc.id}
					>
						<div className="flex items-center justify-between gap-3">
							<div className="flex items-center gap-3">
								<div className="flex h-9 w-9 items-center justify-center rounded-md bg-secondary text-accent">
									<Database className="h-4 w-4" />
								</div>
								<div>
									<p className="font-medium text-foreground text-sm">
										{svc.name}
									</p>
									<p className="text-muted-foreground text-xs">
										{svc.description}
									</p>
								</div>
							</div>
							<div className="text-right">
								<p className="font-mono text-foreground text-sm">:{svc.port}</p>
								<p className="font-mono text-muted-foreground text-[10px]">
									{svc.envVar}
								</p>
							</div>
						</div>
					</div>
				))}
			</div>
		</PreviewFrame>
	);
}

function VariablesPreview() {
	return (
		<PreviewFrame
			icon={KeyRound}
			subtitle="SOPS + AGE · scoped per app and environment"
			title="Variables"
		>
			<div className="grid gap-2">
				{VARIABLE_PREVIEW.map((variable) => (
					<div
						className="rounded-lg border border-border/70 bg-background/60 p-3"
						key={variable.id}
					>
						<div className="flex items-center justify-between gap-3">
							<div className="flex min-w-0 items-center gap-3">
								<span
									className={cn(
										"inline-flex items-center rounded-md px-1.5 py-0.5 font-mono text-[10px] tracking-[0.08em] uppercase",
										VARIABLE_STYLES[variable.kind],
									)}
								>
									{variable.kind}
								</span>
								<div className="min-w-0">
									<p className="truncate font-mono font-semibold text-foreground text-xs">
										{variable.key}
									</p>
									<p className="truncate font-mono text-muted-foreground text-[10px]">
										{variable.masked}
									</p>
								</div>
							</div>
							<span className="shrink-0 rounded-full border border-border/80 px-2 py-0.5 text-[10px] text-muted-foreground">
								{variable.scope}
							</span>
						</div>
					</div>
				))}
			</div>
			<div className="mt-3 flex flex-wrap items-center gap-2 text-muted-foreground text-[10px]">
				<span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5">
					<CheckCircle2 className="h-3 w-3 text-emerald-400" />
					Resolved at shell entry
				</span>
				<span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5">
					<FileCode2 className="h-3 w-3" />
					Type-safe codegen
				</span>
			</div>
		</PreviewFrame>
	);
}

function StudioPreviewRotator() {
	const previews = useMemo<PreviewSlide[]>(
		() => [
			{
				id: "apps",
				label: "Apps",
				tagline: "Apps with stable ports, URLs, and tasks",
				icon: Boxes,
				content: <AppsPreview />,
			},
			{
				id: "services",
				label: "Services",
				tagline: "Postgres, Redis, Minio — orchestrated",
				icon: Server,
				content: <ServicesPreview />,
			},
			{
				id: "variables",
				label: "Variables",
				tagline: "Encrypted secrets + computed config",
				icon: KeyRound,
				content: <VariablesPreview />,
			},
		],
		[],
	);
	const [activeIndex, setActiveIndex] = useState(0);

	useEffect(() => {
		const timer = window.setInterval(() => {
			setActiveIndex((prev) => (prev + 1) % previews.length);
		}, ROTATION_MS);
		return () => window.clearInterval(timer);
	}, [previews.length]);

	return (
		<div className="relative">
			<div className="mb-4 flex items-center justify-between gap-3">
				<div className="flex items-center gap-2 text-muted-foreground text-sm">
					<span className="inline-flex items-center gap-1.5 rounded-full bg-accent/10 px-3 py-1 font-semibold text-accent text-xs tracking-[0.12em] uppercase">
						<Layers className="h-3 w-3" />
						Studio preview
					</span>
					<span className="hidden text-muted-foreground sm:inline">
						{previews[activeIndex]?.tagline}
					</span>
				</div>
				<Link
					className="inline-flex items-center gap-1 text-accent text-sm underline-offset-4 hover:underline"
					to="/studio"
				>
					Open the studio <ArrowRight className="h-3.5 w-3.5" />
				</Link>
			</div>
			<div
				aria-hidden
				className="-z-10 -inset-4 absolute rounded-3xl bg-gradient-to-br from-accent/15 via-transparent to-primary/10 blur-3xl"
			/>
			<div className="relative min-h-[560px] overflow-hidden rounded-2xl border border-border/70 bg-secondary/40 p-2 shadow-2xl">
				<div className="flex items-center gap-2 px-3 pt-1.5 pb-2">
					<div className="flex gap-1.5">
						<span className="h-2.5 w-2.5 rounded-full bg-red-500/70" />
						<span className="h-2.5 w-2.5 rounded-full bg-yellow-500/70" />
						<span className="h-2.5 w-2.5 rounded-full bg-green-500/70" />
					</div>
					<span className="ml-2 inline-flex items-center gap-1.5 rounded-md bg-background/60 px-2 py-0.5 font-mono text-[10px] text-muted-foreground">
						<Terminal className="h-2.5 w-2.5" />
						http://localhost:9876
					</span>
				</div>
				<div className="relative h-[520px]">
					{previews.map((preview, index) => (
						<div
							className={cn(
								"absolute inset-0 transition-all duration-500",
								index === activeIndex
									? "translate-y-0 opacity-100"
									: "pointer-events-none translate-y-4 opacity-0",
							)}
							key={preview.id}
						>
							{preview.content}
						</div>
					))}
				</div>
			</div>
			<div className="mt-4 flex flex-wrap gap-2">
				{previews.map((preview, index) => {
					const Icon = preview.icon;
					return (
						<button
							className={cn(
								"group inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition-colors",
								index === activeIndex
									? "border-accent/60 bg-accent/10 text-foreground"
									: "border-border bg-background/60 text-muted-foreground hover:text-foreground",
							)}
							key={preview.id}
							onClick={() => setActiveIndex(index)}
							type="button"
						>
							<Icon className="h-3.5 w-3.5" />
							{preview.label}
						</button>
					);
				})}
			</div>
		</div>
	);
}

export function HeroSection() {
	return (
		<section className="relative overflow-hidden border-border border-b">
			<div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-accent/10 via-transparent to-transparent" />

			<div className="relative mx-auto max-w-7xl px-4 py-24 sm:px-6 sm:py-32 lg:px-8 lg:py-40">
				<div className="grid gap-12 lg:grid-cols-2 lg:gap-16">
					<div className="flex flex-col justify-center">
						<div className="mb-6 inline-flex w-fit items-center gap-2 rounded-full border border-border bg-secondary px-4 py-1.5">
							<span className="h-2 w-2 rounded-full bg-accent" />
							<span className="text-muted-foreground text-sm">
								Open source · Powered by Nix · Self-hosted
							</span>
						</div>
						<Headline />

						<p className="mt-6 max-w-xl text-pretty text-lg text-muted-foreground leading-relaxed">
							One <span className="font-mono text-foreground">.stack/config.nix</span>
							{" "}replaces dozens of config files. Reproducible dev environments,
							encrypted secrets, deterministic ports, and real HTTPS — generated
							for your whole team.{" "}
							<span className="text-foreground">No Nix knowledge required.</span>
						</p>

						<div className="mt-8 flex flex-wrap gap-3">
							<HeroCTAs />
							<Button asChild size="lg" variant="outline">
								<Link to="/demo">Open Studio demo</Link>
							</Button>
							<Button
								asChild
								className="text-muted-foreground hover:text-foreground"
								size="lg"
								variant="ghost"
							>
								<a
									href="https://github.com/darkmatter/stackpanel"
									rel="noopener noreferrer"
									target="_blank"
								>
									<svg
										aria-hidden
										className="mr-2 h-4 w-4"
										fill="currentColor"
										viewBox="0 0 24 24"
									>
										<path d="M12 0C5.37 0 0 5.37 0 12a12 12 0 008.21 11.39c.6.11.82-.26.82-.58v-2c-3.34.73-4.04-1.61-4.04-1.61-.55-1.39-1.34-1.76-1.34-1.76-1.09-.74.08-.73.08-.73 1.21.08 1.84 1.24 1.84 1.24 1.07 1.84 2.81 1.31 3.5 1 .11-.78.42-1.31.76-1.61-2.66-.31-5.46-1.33-5.46-5.93 0-1.31.47-2.38 1.24-3.22-.13-.31-.54-1.53.12-3.18 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 016 0c2.29-1.55 3.3-1.23 3.3-1.23.66 1.65.25 2.87.12 3.18.77.84 1.24 1.91 1.24 3.22 0 4.61-2.81 5.62-5.48 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.22.7.83.58A12 12 0 0024 12c0-6.63-5.37-12-12-12z" />
									</svg>
									GitHub
								</a>
							</Button>
						</div>

						<div className="mt-10 grid grid-cols-2 gap-x-6 gap-y-3 text-muted-foreground text-sm sm:grid-cols-3">
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								Reproducible
							</div>
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								Self-hosted
							</div>
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								No lock-in
							</div>
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								Local-first
							</div>
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								Works offline
							</div>
							<div className="flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4 text-accent" />
								MIT licensed
							</div>
						</div>
					</div>

					<StudioPreviewRotator />
				</div>
			</div>
		</section>
	);
}

function HeroCTAs() {
	const waitlist = useWaitlist();
	return (
		<Button
			className="bg-foreground text-background hover:bg-foreground/90"
			size="lg"
			onClick={() => waitlist.open({ source: "landing.hero" })}
		>
			Join the beta waitlist <ArrowRight className="ml-2 h-4 w-4" />
		</Button>
	);
}
