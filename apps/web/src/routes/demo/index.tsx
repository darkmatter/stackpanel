import { Link, createFileRoute } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
	AppWindow,
	ArrowRight,
	CheckCircle2,
	Clock,
	Cloud,
	Code2,
	GitBranch,
	KeyRound,
	Network,
	Rocket,
	Server,
	ShieldCheck,
	Terminal,
	Users,
	Variable,
} from "lucide-react";
import { useWaitlist } from "@/components/landing/waitlist-dialog";
import {
	DEMO_ACTIVITY,
	DEMO_APPS,
	DEMO_HEALTH,
	DEMO_PROJECT,
	DEMO_SERVICES,
} from "@/components/demo/demo-fixtures";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/demo/")({
	component: DemoOverview,
});

const activityIconMap = {
	deploy: Rocket,
	secret: KeyRound,
	shell: Terminal,
	code: Code2,
	warn: ShieldCheck,
	user: Users,
} as const;

function DemoOverview() {
	const waitlist = useWaitlist();
	const runningServices = DEMO_SERVICES.filter(
		(s) => s.status === "running",
	).length;
	const runningApps = DEMO_APPS.filter((a) => a.status === "running").length;

	return (
		<div className="mx-auto max-w-7xl space-y-6 p-6">
			<div className="flex flex-wrap items-start justify-between gap-4">
				<div className="space-y-1">
					<p className="text-xs uppercase tracking-[0.16em] text-muted-foreground">
						Project overview
					</p>
					<h1 className="font-bold font-[Montserrat] text-3xl text-foreground tracking-tight">
						{DEMO_PROJECT.name}
					</h1>
					<p className="text-muted-foreground text-sm">
						{DEMO_APPS.length} apps · {DEMO_SERVICES.length} services ·{" "}
						{DEMO_PROJECT.team.length} team members
					</p>
				</div>
				<div className="flex flex-wrap items-center gap-2">
					<Button asChild variant="outline" size="sm">
						<Link to="/demo/apps">
							<AppWindow className="mr-2 h-3.5 w-3.5" />
							View apps
						</Link>
					</Button>
					<Button
						size="sm"
						className="bg-foreground text-background hover:bg-foreground/90"
						onClick={() => waitlist.open({ source: "demo.overview" })}
					>
						Get early access
						<ArrowRight className="ml-2 h-3.5 w-3.5" />
					</Button>
				</div>
			</div>

			<div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
				<HealthMetric
					icon={CheckCircle2}
					label="Devshell"
					value="Healthy"
					detail={`${DEMO_HEALTH.processesUp}/${DEMO_HEALTH.processesTotal} processes up`}
					tone="ok"
				/>
				<HealthMetric
					icon={AppWindow}
					label="Apps running"
					value={`${runningApps}/${DEMO_APPS.length}`}
					detail="1 building (docs)"
					tone="ok"
				/>
				<HealthMetric
					icon={Server}
					label="Services running"
					value={`${runningServices}/${DEMO_SERVICES.length}`}
					detail="Postgres · Redis · MinIO · Caddy"
					tone="ok"
				/>
				<HealthMetric
					icon={KeyRound}
					label="Secrets"
					value={`${DEMO_HEALTH.encryptedFiles} encrypted`}
					detail={`${DEMO_HEALTH.teamRecipients} recipients`}
					tone="ok"
				/>
			</div>

			<div className="grid gap-4 lg:grid-cols-3">
				<Card className="lg:col-span-2">
					<CardHeader className="flex-row items-center justify-between border-b border-border/60 pb-3">
						<CardTitle className="text-sm">Apps</CardTitle>
						<Button asChild variant="ghost" size="sm" className="h-7 text-xs">
							<Link to="/demo/apps">
								Manage
								<ArrowRight className="ml-1 h-3 w-3" />
							</Link>
						</Button>
					</CardHeader>
					<CardContent className="divide-y divide-border/40 p-0">
						{DEMO_APPS.map((app) => (
							<div
								key={app.id}
								className="flex items-center justify-between px-4 py-3"
							>
								<div className="flex min-w-0 items-center gap-3">
									<div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-muted text-foreground">
										<AppWindow className="h-3.5 w-3.5" />
									</div>
									<div className="min-w-0">
										<div className="flex items-center gap-2">
											<p className="font-mono text-sm text-foreground">
												{app.name}
											</p>
											<StatusDot status={app.status} />
										</div>
										<p className="truncate text-xs text-muted-foreground">
											{app.stack}
										</p>
									</div>
								</div>
								<div className="hidden text-right md:block">
									<p className="font-mono text-xs text-foreground">
										{app.domain}
									</p>
									<p className="font-mono text-[10px] text-muted-foreground">
										:{app.port}
									</p>
								</div>
							</div>
						))}
					</CardContent>
				</Card>

				<Card>
					<CardHeader className="border-b border-border/60 pb-3">
						<CardTitle className="text-sm">At a glance</CardTitle>
					</CardHeader>
					<CardContent className="space-y-3 p-4 text-sm">
						<KvRow icon={GitBranch} label="Branch" value={DEMO_PROJECT.branch} />
						<KvRow
							icon={Network}
							label="Base port"
							value={String(DEMO_PROJECT.basePort)}
						/>
						<KvRow
							icon={ShieldCheck}
							label="Flake check"
							value={DEMO_HEALTH.flakeCheck}
							valueClass="text-emerald-300"
						/>
						<KvRow
							icon={Cloud}
							label="Devshell hash"
							value={DEMO_HEALTH.devshellHash}
							mono
						/>
						<KvRow
							icon={Variable}
							label="Open ports"
							value={String(DEMO_HEALTH.openPorts)}
						/>
						<KvRow icon={Users} label="Team" value={`${DEMO_PROJECT.team.length} members`} />
					</CardContent>
				</Card>
			</div>

			<Card>
				<CardHeader className="border-b border-border/60 pb-3">
					<CardTitle className="text-sm">Activity</CardTitle>
				</CardHeader>
				<CardContent className="divide-y divide-border/40 p-0">
					{DEMO_ACTIVITY.map((event, idx) => {
						const Icon = activityIconMap[event.icon];
						return (
							<div
								key={`${event.actor}-${idx}`}
								className="flex items-start gap-3 px-4 py-3"
							>
								<div className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-muted text-foreground">
									<Icon className="h-3 w-3" />
								</div>
								<div className="min-w-0 flex-1">
									<div className="flex flex-wrap items-baseline justify-between gap-x-3">
										<p className="text-sm text-foreground">{event.title}</p>
										<p className="text-[11px] text-muted-foreground">
											<Clock className="mr-1 inline h-3 w-3" />
											{event.at}
										</p>
									</div>
									{event.detail ? (
										<p className="text-xs text-muted-foreground">
											{event.detail}
										</p>
									) : null}
									<p className="mt-0.5 font-mono text-[10px] text-muted-foreground/70">
										{event.actor}
									</p>
								</div>
							</div>
						);
					})}
				</CardContent>
			</Card>
		</div>
	);
}

function HealthMetric({
	icon: Icon,
	label,
	value,
	detail,
	tone = "neutral",
}: {
	icon: React.ElementType;
	label: string;
	value: string;
	detail?: string;
	tone?: "ok" | "warn" | "neutral";
}) {
	const toneClass =
		tone === "ok"
			? "text-emerald-300"
			: tone === "warn"
				? "text-amber-300"
				: "text-foreground";
	return (
		<Card>
			<CardContent className="space-y-2 p-4">
				<div className="flex items-center justify-between">
					<p className="text-xs uppercase tracking-[0.12em] text-muted-foreground">
						{label}
					</p>
					<div className={cn("flex h-7 w-7 items-center justify-center rounded-md bg-muted", toneClass)}>
						<Icon className="h-3.5 w-3.5" />
					</div>
				</div>
				<p className={cn("font-bold font-[Montserrat] text-2xl tracking-tight", toneClass)}>
					{value}
				</p>
				{detail ? (
					<p className="text-xs text-muted-foreground">{detail}</p>
				) : null}
			</CardContent>
		</Card>
	);
}

function StatusDot({ status }: { status: "running" | "stopped" | "building" }) {
	const map: Record<typeof status, { bg: string; label: string }> = {
		running: { bg: "bg-emerald-400", label: "Running" },
		stopped: { bg: "bg-muted-foreground", label: "Stopped" },
		building: { bg: "bg-amber-400 animate-pulse", label: "Building" },
	};
	const cfg = map[status];
	return (
		<Badge
			variant="outline"
			className="gap-1.5 border-border/60 px-1.5 py-0 text-[10px] font-normal text-muted-foreground"
		>
			<span className={cn("h-1.5 w-1.5 rounded-full", cfg.bg)} />
			{cfg.label}
		</Badge>
	);
}

function KvRow({
	icon: Icon,
	label,
	value,
	mono,
	valueClass,
}: {
	icon: React.ElementType;
	label: string;
	value: string;
	mono?: boolean;
	valueClass?: string;
}) {
	return (
		<div className="flex items-center justify-between gap-3 text-sm">
			<span className="flex items-center gap-2 text-muted-foreground">
				<Icon className="h-3 w-3" />
				{label}
			</span>
			<span
				className={cn(
					"truncate text-foreground",
					mono && "font-mono text-xs",
					valueClass,
				)}
			>
				{value}
			</span>
		</div>
	);
}
