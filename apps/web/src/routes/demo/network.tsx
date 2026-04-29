import { createFileRoute } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
	ArrowRight,
	Globe2,
	Lock,
	Network,
	ShieldCheck,
} from "lucide-react";
import {
	DEMO_NETWORK_ROUTES,
	DEMO_PROJECT,
} from "@/components/demo/demo-fixtures";

export const Route = createFileRoute("/demo/network")({
	component: DemoNetworkPage,
});

function DemoNetworkPage() {
	return (
		<div className="mx-auto max-w-7xl space-y-6 p-6">
			<div className="space-y-1">
				<p className="text-xs uppercase tracking-[0.16em] text-muted-foreground">
					Network
				</p>
				<h1 className="font-bold font-[Montserrat] text-3xl text-foreground tracking-tight">
					Real domains, real TLS, all local
				</h1>
				<p className="text-muted-foreground text-sm">
					Caddy reverse-proxies <span className="font-mono">*.acme.local</span>{" "}
					to your dev ports. Step CA issues per-device certs your OS already
					trusts. No more <span className="font-mono">localhost:5173</span>{" "}
					gymnastics.
				</p>
			</div>

			<div className="grid gap-4 md:grid-cols-3">
				<MetricCard
					icon={Globe2}
					label="Apex domain"
					value={`${DEMO_PROJECT.name}.local`}
					mono
				/>
				<MetricCard
					icon={Network}
					label="Active routes"
					value={`${DEMO_NETWORK_ROUTES.length}`}
				/>
				<MetricCard
					icon={ShieldCheck}
					label="TLS"
					value="Step CA · per-device"
				/>
			</div>

			<Card>
				<CardHeader className="border-b border-border/60 pb-3">
					<CardTitle className="text-sm">Caddy routes</CardTitle>
				</CardHeader>
				<CardContent className="p-0">
					<table className="w-full text-sm">
						<thead className="border-b border-border/60 bg-muted/30 text-left text-[11px] uppercase tracking-[0.12em] text-muted-foreground">
							<tr>
								<th className="px-4 py-2 font-medium">Host</th>
								<th className="hidden px-4 py-2 font-medium md:table-cell">
									Forwards to
								</th>
								<th className="hidden px-4 py-2 font-medium md:table-cell">
									App
								</th>
								<th className="px-4 py-2 font-medium">TLS</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-border/40">
							{DEMO_NETWORK_ROUTES.map((route) => (
								<tr key={route.host} className="hover:bg-muted/20">
									<td className="px-4 py-3">
										<div className="flex items-center gap-2">
											<Globe2 className="h-3 w-3 text-muted-foreground" />
											<span className="font-mono text-xs text-foreground">
												{route.host}
											</span>
										</div>
										{route.notes ? (
											<p className="mt-0.5 text-xs text-muted-foreground">
												{route.notes}
											</p>
										) : null}
									</td>
									<td className="hidden px-4 py-3 md:table-cell">
										<div className="flex items-center gap-2 text-xs text-muted-foreground">
											<ArrowRight className="h-3 w-3" />
											<span className="font-mono text-foreground">
												{route.target}
											</span>
										</div>
									</td>
									<td className="hidden px-4 py-3 md:table-cell">
										{route.app ? (
											<Badge
												variant="outline"
												className="border-accent/30 bg-accent/10 px-1.5 py-0 text-[10px] font-normal text-accent"
											>
												{route.app}
											</Badge>
										) : (
											<span className="text-muted-foreground">—</span>
										)}
									</td>
									<td className="px-4 py-3">
										{route.tls ? (
											<Badge
												variant="outline"
												className="gap-1 border-emerald-500/30 bg-emerald-500/10 px-1.5 py-0 text-[10px] font-normal text-emerald-300"
											>
												<Lock className="h-2.5 w-2.5" />
												step-ca
											</Badge>
										) : (
											<Badge
												variant="outline"
												className="border-border/60 px-1.5 py-0 text-[10px] font-normal text-muted-foreground"
											>
												http
											</Badge>
										)}
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</CardContent>
			</Card>

			<Card>
				<CardContent className="space-y-3 p-4">
					<div className="flex items-start gap-3">
						<ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-300" />
						<div>
							<p className="font-medium text-foreground text-sm">
								Browsers trust your dev URLs without warnings
							</p>
							<p className="text-xs text-muted-foreground">
								Stackpanel runs a project-scoped Step CA and installs the root
								into your OS trust store on first devshell entry. WebAuthn,
								secure cookies and HTTPS-only APIs all just work — locally.
							</p>
						</div>
					</div>
				</CardContent>
			</Card>
		</div>
	);
}

function MetricCard({
	icon: Icon,
	label,
	value,
	mono,
}: {
	icon: React.ElementType;
	label: string;
	value: string;
	mono?: boolean;
}) {
	return (
		<Card>
			<CardContent className="space-y-2 p-4">
				<div className="flex items-center justify-between">
					<p className="text-xs uppercase tracking-[0.12em] text-muted-foreground">
						{label}
					</p>
					<div className="flex h-7 w-7 items-center justify-center rounded-md bg-muted text-foreground">
						<Icon className="h-3.5 w-3.5" />
					</div>
				</div>
				<p
					className={
						mono
							? "font-mono font-medium text-foreground text-base"
							: "font-bold font-[Montserrat] text-foreground text-2xl tracking-tight"
					}
				>
					{value}
				</p>
			</CardContent>
		</Card>
	);
}
