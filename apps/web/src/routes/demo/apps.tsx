import { createFileRoute } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
	AppWindow,
	ArrowUpRight,
	Cloud,
	GitCommit,
	Globe2,
	Play,
	RefreshCw,
	Square,
} from "lucide-react";
import { toast } from "sonner";
import { DEMO_APPS, type DemoApp } from "@/components/demo/demo-fixtures";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/demo/apps")({
	component: DemoAppsPage,
});

function DemoAppsPage() {
	return (
		<div className="mx-auto max-w-7xl space-y-6 p-6">
			<div className="flex flex-wrap items-start justify-between gap-3">
				<div className="space-y-1">
					<p className="text-xs uppercase tracking-[0.16em] text-muted-foreground">
						Apps
					</p>
					<h1 className="font-bold font-[Montserrat] text-3xl text-foreground tracking-tight">
						{DEMO_APPS.length} apps in this stack
					</h1>
					<p className="text-muted-foreground text-sm">
						Each app gets a deterministic port, a real{" "}
						<span className="font-mono">*.acme.local</span> domain via Caddy,
						and a wired-up env package via{" "}
						<span className="font-mono">@gen/env</span>.
					</p>
				</div>
				<Button
					variant="outline"
					size="sm"
					onClick={() => toast.info("Demo mode — refresh is a no-op.")}
				>
					<RefreshCw className="mr-2 h-3.5 w-3.5" />
					Refresh
				</Button>
			</div>

			<div className="grid gap-4 lg:grid-cols-2">
				{DEMO_APPS.map((app) => (
					<AppCard key={app.id} app={app} />
				))}
			</div>
		</div>
	);
}

function AppCard({ app }: { app: DemoApp }) {
	return (
		<Card>
			<CardHeader className="flex-row items-start justify-between border-b border-border/60 pb-4">
				<div className="flex min-w-0 items-start gap-3">
					<div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-accent/15 text-accent">
						<AppWindow className="h-4 w-4" />
					</div>
					<div className="min-w-0">
						<div className="flex items-center gap-2">
							<CardTitle className="font-mono text-base text-foreground">
								{app.name}
							</CardTitle>
							<StatusBadge status={app.status} />
						</div>
						<p className="text-xs text-muted-foreground">{app.stack}</p>
					</div>
				</div>
				<div className="flex items-center gap-1">
					<Button
						size="sm"
						variant="ghost"
						className="h-7 text-xs"
						onClick={() =>
							toast.info(
								"Demo mode — start/stop sends a real `process-compose` signal in the live Studio.",
							)
						}
					>
						{app.status === "running" ? (
							<>
								<Square className="mr-1 h-3 w-3" /> Stop
							</>
						) : (
							<>
								<Play className="mr-1 h-3 w-3" /> Start
							</>
						)}
					</Button>
				</div>
			</CardHeader>
			<CardContent className="space-y-3 p-4 text-sm">
				<KvRow icon={Globe2} label="Local URL">
					<a
						href={app.url}
						target="_blank"
						rel="noreferrer noopener"
						className="font-mono text-xs text-foreground underline-offset-4 hover:text-accent hover:underline"
						onClick={(e) => {
							e.preventDefault();
							toast.info(
								`In a real Stackpanel devshell, ${app.domain} resolves to localhost:${app.port} with TLS.`,
							);
						}}
					>
						{app.url}
						<ArrowUpRight className="ml-1 inline h-3 w-3" />
					</a>
				</KvRow>
				<KvRow icon={Globe2} label="Port">
					<span className="font-mono text-xs text-foreground">{app.port}</span>
				</KvRow>
				{app.previewUrl ? (
					<KvRow icon={Cloud} label="Preview">
						<span className="font-mono text-xs text-muted-foreground">
							{app.previewUrl}
						</span>
					</KvRow>
				) : null}
				{app.deployTarget ? (
					<KvRow icon={Cloud} label="Deploy target">
						<Badge
							variant="outline"
							className="border-border/60 px-1.5 py-0 text-[10px] text-muted-foreground"
						>
							{app.deployTarget}
						</Badge>
					</KvRow>
				) : null}
				<KvRow icon={GitCommit} label="HEAD">
					<span className="font-mono text-xs text-muted-foreground">
						{app.commit}
					</span>
				</KvRow>
				{app.uptime ? (
					<KvRow icon={Globe2} label="Uptime">
						<span className="text-xs text-muted-foreground">{app.uptime}</span>
					</KvRow>
				) : null}
			</CardContent>
		</Card>
	);
}

function KvRow({
	icon: Icon,
	label,
	children,
}: {
	icon: React.ElementType;
	label: string;
	children: React.ReactNode;
}) {
	return (
		<div className="flex items-center justify-between gap-3">
			<span className="flex items-center gap-2 text-muted-foreground">
				<Icon className="h-3 w-3" />
				{label}
			</span>
			<span className="min-w-0 truncate text-right">{children}</span>
		</div>
	);
}

function StatusBadge({
	status,
}: {
	status: "running" | "stopped" | "building";
}) {
	const map = {
		running: { color: "bg-emerald-400", label: "Running" },
		stopped: { color: "bg-muted-foreground", label: "Stopped" },
		building: { color: "bg-amber-400 animate-pulse", label: "Building" },
	} as const;
	const cfg = map[status];
	return (
		<Badge
			variant="outline"
			className="gap-1.5 border-border/60 px-1.5 py-0 text-[10px] font-normal text-muted-foreground"
		>
			<span className={cn("h-1.5 w-1.5 rounded-full", cfg.color)} />
			{cfg.label}
		</Badge>
	);
}
