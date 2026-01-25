import { Link } from "@tanstack/react-router";
import { Avatar, AvatarFallback } from "@ui/avatar";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import { ArrowRight, CheckCircle2, Code, Globe2, Layers, Server } from "lucide-react";
import { type ReactNode, useEffect, useMemo, useState } from "react";
import { AppTasks } from "@/components/studio/panels/apps";
import { PanelHeader } from "@/components/studio/panels/shared/panel-header";
import { PackageCard } from "@/components/studio/panels/packages/components";
import { getTypeConfig } from "@/components/studio/panels/variables/constants";
import type { NixpkgsPackage } from "@/lib/types";

// AppTask interface for demo/preview data
interface AppTask {
	key: string;
	command: string;
	env?: Record<string, string>;
}
import { cn } from "@/lib/utils";

function Headline() {
	return (
		<h1 className="text-balance font-bold text-4xl text-foreground tracking-tight sm:text-5xl lg:text-6xl font-[Montserrat] -mt-4">
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
				className="text-accent font-bold italic"
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
				not{" "}plumbing.
			</span>
			{/* <span
				className="font-bold "
				style={{
					fontVariationSettings: '"wght" 482',
					textUnderlineOffset: "5px",
					textDecorationThickness: "from-font",
					letterSpacing: "-0.1rem",
				}}
			>
				plumbing
			</span> */}
		</h1>
	);
}
//   {/*// style="
//   //   font-variation-settings: &quot;wght&quot; 210;
//   //   font-weight: unset;
//   //   font-feature-settings: &quot;calt&quot; 1;
//   //   font-family: &quot;Montserrat&quot;;
//   //   letter-spacing: -0.15rem;
//   //   line-height: 4.6rem;
// // ">Build <span class="font-bold text-accent" style="
// //     font-weight: unset;
// //     font-variation-settings: &quot;wght&quot; 807;
// //     font-style: italic;
// //     text-decoration: underline;
// //     text-underline-offset: 5px;
// //     text-decoration-thickness: from-font;
// //     letter-spacing: -0.05rem;
// //     /* color: hsl(0,0%,90%); */
// // ">products,</span><span class="font-bold text-accent" style="
// //     font-weight: unset;
// //     font-variation-settings: &quot;wght&quot; 592;
// //     /* font-style: italic; */
// //     /* text-decoration: underline; */
// //     text-underline-offset: 5px;
// //     text-decoration-thickness: from-font;
// //     letter-spacing: -0.10rem;
// //     color: hsl(0,0%,90%);
// // "> <span style="
// //     font-variation-settings: &quot;wght&quot; 398;
// //     letter-spacing: -0.1rem;
// //     font-style: normal;
// //     color: hsl(0,0%,90%);
// // ">not</span> plumbing.</span></h1>*/}

const PACKAGE_PREVIEW: NixpkgsPackage[] = [
	{
		name: "postgresql",
		attr_path: "pkgs.postgresql_16",
		version: "16.3",
		description: "Production-grade relational database with extensions support.",
		license: "PostgreSQL",
		homepage: "https://www.postgresql.org/",
	},
	{
		name: "redis",
		attr_path: "pkgs.redis",
		version: "7.2.4",
		description: "In-memory data structure store used as a cache, database, and message broker.",
		license: "BSD-3-Clause",
		homepage: "https://redis.io/",
	},
	{
		name: "bun",
		attr_path: "pkgs.bun",
		version: "1.1.8",
		description: "Fast JavaScript runtime, bundler, and test runner.",
		license: "MIT",
		homepage: "https://bun.sh/",
	},
	{
		name: "caddy",
		attr_path: "pkgs.caddy",
		version: "2.7.6",
		description: "Extensible web server with automatic HTTPS and great defaults.",
		license: "Apache-2.0",
		homepage: "https://caddyserver.com/",
	},
];

type AppPreview = {
	id: string;
	name: string;
	stack: string;
	status: "running" | "staging" | "deploying";
	domain: string;
	port: number;
	tasks: Record<string, AppTask>;
};

const APP_PREVIEW: AppPreview[] = [
	{
		id: "api",
		name: "api-gateway",
		stack: "Bun · SST",
		status: "running",
		domain: "api.stackpanel.local",
		port: 6401,
		tasks: {
			dev: { key: "dev", command: "bun run dev", env: {} },
			test: { key: "test", command: "bun test", env: {} },
		},
	},
	{
		id: "web",
		name: "web",
		stack: "React · TanStack",
		status: "staging",
		domain: "web.stackpanel.local",
		port: 6402,
		tasks: {
			dev: { key: "dev", command: "bun run dev -- --host", env: {} },
			lint: { key: "lint", command: "bun run lint", env: {} },
		},
	},
	{
		id: "worker",
		name: "queue-worker",
		stack: "Go · Temporal",
		status: "deploying",
		domain: "worker.stackpanel.local",
		port: 6410,
		tasks: {
			dev: { key: "dev", command: "go run ./cmd/worker", env: {} },
		},
	},
];

type VariablePreview = {
	id: string;
	key: string;
	type: string;
	description: string;
	environments: string[];
	linkedApps: string[];
};

const VARIABLE_PREVIEW: VariablePreview[] = [
	{
		id: "DATABASE_URL",
		key: "DATABASE_URL",
		type: "secret",
		description: "Encrypted connection string for primary Postgres cluster.",
		environments: ["dev", "staging", "prod"],
		linkedApps: ["api-gateway", "queue-worker"],
	},
	{
		id: "NEXT_PUBLIC_API_URL",
		key: "NEXT_PUBLIC_API_URL",
		type: "config",
		description: "Public API endpoint exposed to frontend clients.",
		environments: ["dev", "staging"],
		linkedApps: ["web"],
	},
	{
		id: "TS_AUTH_DOMAIN",
		key: "TS_AUTH_DOMAIN",
		type: "service",
		description: "Tailscale auth domain issued by Stackpanel network.",
		environments: ["dev"],
		linkedApps: ["web", "api-gateway"],
	},
];

type PreviewSlide = {
	id: string;
	label: string;
	tagline: string;
	content: ReactNode;
};

const ROTATION_MS = 6200;

function PackagesPreview() {
	return (
		<div className="space-y-4 rounded-xl border border-border/70 bg-card p-5">
			<PanelHeader
				title="Packages"
				description="Pinned runtimes, services, and tooling from nixpkgs"
				guideKey="packages"
			/>
			<div className="grid gap-3 md:grid-cols-2">
				{PACKAGE_PREVIEW.map((pkg) => (
					<PackageCard key={pkg.name} pkg={pkg} isCompact />
				))}
			</div>
			<div className="flex flex-wrap items-center gap-3 text-muted-foreground text-xs">
				<span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2.5 py-1 font-medium text-foreground">
					<CheckCircle2 className="h-3 w-3 text-accent" />
					Cached in devshell
				</span>
				<span className="inline-flex items-center gap-1">
					<Server className="h-3 w-3" />
					Services + runtimes, side-by-side
				</span>
				<span className="inline-flex items-center gap-1">
					<Layers className="h-3 w-3" />
					Deterministic channels
				</span>
			</div>
		</div>
	);
}

function AppsPreview() {
	const statusStyles: Record<AppPreview["status"], string> = {
		running: "border-emerald-400/40 bg-emerald-500/15 text-emerald-300",
		staging: "border-amber-400/30 bg-amber-500/10 text-amber-300",
		deploying: "border-blue-400/30 bg-blue-500/10 text-blue-300",
	};

	return (
		<div className="space-y-4 rounded-xl border border-border/70 bg-card p-5">
			<PanelHeader
				title="Apps"
				description="Monorepo-aware tasks with stable ports"
				guideKey="apps"
			/>
			<div className="grid gap-3">
				{APP_PREVIEW.map((app) => (
					<Card key={app.id}>
						<CardContent className="p-4 space-y-3">
							<div className="flex items-center justify-between gap-3">
								<div className="flex items-center gap-3">
									<Avatar className="h-10 w-10">
										<AvatarFallback className="bg-secondary text-foreground">
											{app.name
												.split("-")
												.map((part) => part[0])
												.join("")
												.slice(0, 2)
												.toUpperCase()}
										</AvatarFallback>
									</Avatar>
									<div>
										<p className="font-medium text-foreground">{app.name}</p>
										<p className="text-muted-foreground text-xs">{app.stack}</p>
									</div>
								</div>
								<Badge
									className={cn(
										"border text-xs",
										statusStyles[app.status],
									)}
									variant="outline"
								>
									{app.status}
								</Badge>
							</div>

							<div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
								<span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2.5 py-1 text-foreground">
									<Globe2 className="h-3 w-3" />
									{app.domain}
								</span>
								<span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2.5 py-1 text-foreground">
									<Code className="h-3 w-3" />
									Port {app.port}
								</span>
							</div>

							<div className="border-t border-border/60 pt-3">
								<AppTasks tasks={app.tasks} />
							</div>
						</CardContent>
					</Card>
				))}
			</div>
		</div>
	);
}

function VariablesPreview() {
	return (
		<div className="space-y-4 rounded-xl border border-border/70 bg-card p-5">
			<PanelHeader
				title="Variables"
				description="Secrets, config, and service values with scoped access"
				guideKey="variables"
			/>
			<div className="grid gap-3">
				{VARIABLE_PREVIEW.map((variable) => {
					const typeConfig = getTypeConfig(variable.type);
					const Icon = typeConfig.icon;

					return (
						<Card key={variable.id}>
							<CardContent className="space-y-3 p-4">
								<div className="flex items-center justify-between gap-3">
									<div className="flex items-center gap-3">
										<div
											className={cn(
												"flex h-10 w-10 items-center justify-center rounded-lg",
												typeConfig.color,
											)}
										>
											<Icon className="h-4 w-4" />
										</div>
										<div>
											<p className="font-semibold text-foreground">
												{variable.key}
											</p>
											<p className="text-muted-foreground text-xs">
												{variable.description}
											</p>
										</div>
									</div>
									<Badge variant="outline" className="text-xs capitalize">
										{typeConfig.label}
									</Badge>
								</div>

								<div className="flex flex-wrap items-center gap-2 text-xs">
									<div className="inline-flex items-center gap-1 rounded-full border border-border/80 px-2 py-1">
										<CheckCircle2 className="h-3 w-3 text-accent" />
										<span className="text-muted-foreground">Environments</span>
										<div className="flex gap-1">
											{variable.environments.map((env) => (
												<Badge key={env} variant="secondary" className="text-[10px]">
													{env}
												</Badge>
											))}
										</div>
									</div>
									<div className="inline-flex items-center gap-1 rounded-full border border-border/80 px-2 py-1">
										<span className="text-muted-foreground">Linked apps</span>
										<div className="flex gap-1">
											{variable.linkedApps.map((app) => (
												<Badge key={app} variant="outline" className="text-[10px]">
													{app}
												</Badge>
											))}
										</div>
									</div>
								</div>
							</CardContent>
						</Card>
					);
				})}
			</div>
		</div>
	);
}

function StudioPreviewRotator() {
	const previews = useMemo<PreviewSlide[]>(
		() => [
			{
				id: "packages",
				label: "Packages",
				tagline: "Pin runtimes, services, and tools to devshell",
				content: <PackagesPreview />,
			},
			{
				id: "apps",
				label: "Apps",
				tagline: "Ports, domains, and tasks ready to ship",
				content: <AppsPreview />,
			},
			{
				id: "variables",
				label: "Variables",
				tagline: "Secrets + config scoped per environment",
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
			<div className="mb-4 flex items-center justify-between">
				<div className="flex items-center gap-2 text-muted-foreground text-sm">
					<span className="rounded-full bg-accent/10 px-3 py-1 text-accent text-xs font-semibold tracking-[0.1em]">
						Studio previews
					</span>
					<span className="text-muted-foreground">
						{previews[activeIndex]?.tagline}
					</span>
				</div>
				<Link
					className="text-accent text-sm underline-offset-4 hover:underline"
					to="/studio"
				>
					Open the studio
				</Link>
			</div>
			<div className="relative min-h-[560px] overflow-hidden rounded-2xl border border-border/70 bg-secondary/40 p-2 shadow-2xl">
				{previews.map((preview, index) => (
					<div
						className={cn(
							"absolute inset-2 transition-all duration-500",
							index === activeIndex
								? "opacity-100 translate-y-0"
								: "pointer-events-none opacity-0 translate-y-6",
						)}
						key={preview.id}
					>
						{preview.content}
					</div>
				))}
			</div>
			<div className="mt-4 flex flex-wrap gap-2">
				{previews.map((preview, index) => (
					<button
						className={cn(
							"group relative overflow-hidden rounded-full border px-3 py-1.5 text-sm transition-colors",
							index === activeIndex
								? "border-accent/60 bg-accent/10 text-foreground"
								: "border-border bg-background/60 text-muted-foreground hover:text-foreground",
						)}
						key={preview.id}
						onClick={() => setActiveIndex(index)}
						type="button"
					>
						<span
							className={cn(
								"absolute inset-0 z-0 bg-accent/10 transition-opacity",
								index === activeIndex ? "opacity-100" : "opacity-0",
							)}
						/>
						<span className="relative z-10">{preview.label}</span>
					</button>
				))}
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
								The new localhost:3001
							</span>
						</div>
						<Headline />
						{/*<h1 className="text-balance font-bold text-4xl text-foreground tracking-tight sm:text-5xl lg:text-6xl">
              Build <span className="font-bold text-accent">products</span> not
              plumbing.
            </h1>*/}

						<p className="mt-6 max-w-xl text-pretty text-lg text-muted-foreground leading-relaxed">
							From idea to production-ready app. StackPanel unifies
							infrastructure, tooling, secrets, and local development into one
							internal platform your whole team can access.
						</p>

						<div className="mt-8 flex flex-wrap gap-4">
							<Button
								asChild
								className="bg-foreground text-background hover:bg-foreground/90"
								size="lg"
							>
								<Link to="/login">
									Get Started <ArrowRight className="ml-2 h-4 w-4" />
								</Link>
							</Button>
							<Button asChild size="lg" variant="outline">
								<Link to="/studio">Instant Demo</Link>
							</Button>
						</div>

						<div className="mt-8 flex items-center gap-6 text-muted-foreground text-sm">
							<div className="flex items-center gap-2">
								<span className="h-1.5 w-1.5 rounded-full bg-accent" />
								Self-hosted
							</div>
							<div className="flex items-center gap-2">
								<span className="h-1.5 w-1.5 rounded-full bg-accent" />
								Zero vendor lock-in
							</div>
							<div className="flex items-center gap-2">
								<span className="h-1.5 w-1.5 rounded-full bg-accent" />
								Cost-effective
							</div>
						</div>
					</div>

					<StudioPreviewRotator />
				</div>
			</div>
		</section>
	);
}
