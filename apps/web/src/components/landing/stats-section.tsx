import { FileCode2, Hash, Layers, Network } from "lucide-react";

export function StatsSection() {
	const stats = [
		{
			icon: FileCode2,
			value: "1",
			label: "config file",
			detail: ".stack/config.nix declares it all",
		},
		{
			icon: Hash,
			value: "Deterministic",
			label: "ports",
			detail: "Hashed from project name",
		},
		{
			icon: Network,
			value: "60+",
			label: "agent endpoints",
			detail: "REST + Connect-RPC + SSE",
		},
		{
			icon: Layers,
			value: "Zero",
			label: "vendor lock-in",
			detail: "Generated files look hand-written",
		},
	];

	return (
		<section className="border-border border-b bg-secondary/30">
			<div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
				<div className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border lg:grid-cols-4">
					{stats.map((stat) => (
						<div
							className="bg-background/40 p-6 text-center transition-colors hover:bg-background/60"
							key={stat.label}
						>
							<div className="mx-auto flex h-9 w-9 items-center justify-center rounded-lg bg-accent/10 text-accent">
								<stat.icon className="h-4 w-4" />
							</div>
							<p className="mt-3 font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
								{stat.value}
							</p>
							<p className="mt-1 font-medium text-foreground text-sm">
								{stat.label}
							</p>
							<p className="mt-1 text-muted-foreground text-xs">
								{stat.detail}
							</p>
						</div>
					))}
				</div>
			</div>
		</section>
	);
}
