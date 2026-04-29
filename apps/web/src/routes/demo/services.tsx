import { createFileRoute } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import {
	Cpu,
	Database,
	HardDrive,
	Network,
	Play,
	RefreshCw,
	Server,
	ShieldCheck,
	Square,
	Workflow,
} from "lucide-react";
import { toast } from "sonner";
import { DEMO_SERVICES, type DemoService } from "@/components/demo/demo-fixtures";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/demo/services")({
	component: DemoServicesPage,
});

const kindMap: Record<DemoService["kind"], { icon: React.ElementType; label: string }> = {
	global: { icon: Database, label: "Global service" },
	network: { icon: Network, label: "Network" },
	orchestrator: { icon: Workflow, label: "Orchestrator" },
};

function DemoServicesPage() {
	return (
		<div className="mx-auto max-w-7xl space-y-6 p-6">
			<div className="flex flex-wrap items-start justify-between gap-3">
				<div className="space-y-1">
					<p className="text-xs uppercase tracking-[0.16em] text-muted-foreground">
						Services
					</p>
					<h1 className="font-bold font-[Montserrat] text-3xl text-foreground tracking-tight">
						Real services. Local ports. No Docker required.
					</h1>
					<p className="text-muted-foreground text-sm">
						Stackpanel orchestrates these via{" "}
						<span className="font-mono">process-compose</span>. Each one gets a
						deterministic port and an env var your apps can read directly.
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

			<Card className="overflow-hidden">
				<CardContent className="p-0">
					<table className="w-full text-sm">
						<thead className="border-b border-border/60 bg-muted/30 text-left text-[11px] uppercase tracking-[0.12em] text-muted-foreground">
							<tr>
								<th className="px-4 py-2 font-medium">Service</th>
								<th className="hidden px-4 py-2 font-medium md:table-cell">
									Kind
								</th>
								<th className="px-4 py-2 font-medium">Status</th>
								<th className="hidden px-4 py-2 font-medium lg:table-cell">
									Port / env
								</th>
								<th className="hidden px-4 py-2 font-medium lg:table-cell">
									Resources
								</th>
								<th className="px-4 py-2"></th>
							</tr>
						</thead>
						<tbody className="divide-y divide-border/40">
							{DEMO_SERVICES.map((svc) => {
								const KindIcon = kindMap[svc.kind].icon;
								return (
									<tr key={svc.id} className="hover:bg-muted/20">
										<td className="px-4 py-3">
											<div className="flex items-center gap-3">
												<div className="flex h-7 w-7 items-center justify-center rounded-md bg-accent/10 text-accent">
													<Server className="h-3 w-3" />
												</div>
												<div>
													<p className="font-medium text-foreground">
														{svc.name}
													</p>
													{svc.notes ? (
														<p className="text-xs text-muted-foreground">
															{svc.notes}
														</p>
													) : null}
												</div>
											</div>
										</td>
										<td className="hidden px-4 py-3 md:table-cell">
											<Badge
												variant="outline"
												className="gap-1 border-border/60 px-1.5 py-0 text-[10px] font-normal text-muted-foreground"
											>
												<KindIcon className="h-3 w-3" />
												{kindMap[svc.kind].label}
											</Badge>
										</td>
										<td className="px-4 py-3">
											<StatusBadge status={svc.status} uptime={svc.uptime} />
										</td>
										<td className="hidden px-4 py-3 lg:table-cell">
											{svc.port ? (
												<div>
													<p className="font-mono text-xs text-foreground">
														:{svc.port}
													</p>
													{svc.envVar ? (
														<p className="font-mono text-[10px] text-muted-foreground">
															{svc.envVar}
														</p>
													) : null}
												</div>
											) : (
												<span className="text-muted-foreground">—</span>
											)}
										</td>
										<td className="hidden px-4 py-3 lg:table-cell">
											<div className="flex flex-col gap-0.5 text-xs text-muted-foreground">
												{svc.cpu ? (
													<span className="flex items-center gap-1">
														<Cpu className="h-3 w-3" /> {svc.cpu}
													</span>
												) : null}
												{svc.memory ? (
													<span className="flex items-center gap-1">
														<HardDrive className="h-3 w-3" /> {svc.memory}
													</span>
												) : null}
											</div>
										</td>
										<td className="px-4 py-3 text-right">
											<Button
												size="sm"
												variant="ghost"
												className="h-7 text-xs"
												onClick={() =>
													toast.info(
														"Demo mode — service control sends signals via process-compose in the live Studio.",
													)
												}
											>
												{svc.status === "running" ? (
													<>
														<Square className="mr-1 h-3 w-3" /> Stop
													</>
												) : (
													<>
														<Play className="mr-1 h-3 w-3" /> Start
													</>
												)}
											</Button>
										</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</CardContent>
			</Card>

			<Card>
				<CardContent className="space-y-2 p-4 text-sm">
					<div className="flex items-start gap-3">
						<ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-300" />
						<div>
							<p className="font-medium text-foreground">
								All services come from your Nix flake
							</p>
							<p className="text-xs text-muted-foreground">
								No Docker daemon, no runtime drift. The same packages your team
								gets via{" "}
								<span className="font-mono">stack.globalServices.postgres</span>{" "}
								or <span className="font-mono">stack.globalServices.redis</span>{" "}
								land on every machine, every time.
							</p>
						</div>
					</div>
				</CardContent>
			</Card>
		</div>
	);
}

function StatusBadge({
	status,
	uptime,
}: {
	status: "running" | "stopped";
	uptime?: string;
}) {
	if (status === "running") {
		return (
			<Badge
				variant="outline"
				className="gap-1.5 border-emerald-500/30 bg-emerald-500/10 px-1.5 py-0 text-[10px] font-normal text-emerald-300"
			>
				<span className={cn("h-1.5 w-1.5 rounded-full bg-emerald-400")} />
				Running
				{uptime ? (
					<span className="text-emerald-300/60">· {uptime}</span>
				) : null}
			</Badge>
		);
	}
	return (
		<Badge
			variant="outline"
			className="gap-1.5 border-border/60 px-1.5 py-0 text-[10px] font-normal text-muted-foreground"
		>
			<span className="h-1.5 w-1.5 rounded-full bg-muted-foreground" />
			Stopped
		</Badge>
	);
}
