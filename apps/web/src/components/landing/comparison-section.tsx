import { Check, Minus, X } from "lucide-react";

type Cell = "yes" | "partial" | "no";

type Row = {
	feature: string;
	detail?: string;
	stackpanel: Cell;
	devenv: Cell;
	docker: Cell;
	paas: Cell;
};

const rows: Row[] = [
	{
		feature: "Reproducible across machines",
		detail: "Same Bun, Go, Postgres versions",
		stackpanel: "yes",
		devenv: "yes",
		docker: "partial",
		paas: "no",
	},
	{
		feature: "Deterministic shared ports",
		detail: "Same ports on every laptop",
		stackpanel: "yes",
		devenv: "no",
		docker: "no",
		paas: "no",
	},
	{
		feature: "Real HTTPS in dev",
		detail: "Internal CA + reverse proxy",
		stackpanel: "yes",
		devenv: "no",
		docker: "no",
		paas: "yes",
	},
	{
		feature: "Encrypted secrets in repo",
		detail: "SOPS + AGE recipients in Nix",
		stackpanel: "yes",
		devenv: "partial",
		docker: "no",
		paas: "no",
	},
	{
		feature: "Type-safe env per app",
		detail: "Generated TS / Go / Python",
		stackpanel: "yes",
		devenv: "no",
		docker: "no",
		paas: "no",
	},
	{
		feature: "IDE settings & extensions",
		detail: "VS Code + Zed, version-controlled",
		stackpanel: "yes",
		devenv: "no",
		docker: "no",
		paas: "no",
	},
	{
		feature: "Visual studio for the team",
		detail: "Web UI for non-Nix users",
		stackpanel: "yes",
		devenv: "no",
		docker: "no",
		paas: "yes",
	},
	{
		feature: "Maintained deployment recipes",
		detail: "Production Stacks updated for you",
		stackpanel: "yes",
		devenv: "no",
		docker: "no",
		paas: "partial",
	},
	{
		feature: "No vendor lock-in",
		detail: "Eject and the repo still works",
		stackpanel: "yes",
		devenv: "yes",
		docker: "yes",
		paas: "no",
	},
	{
		feature: "Self-hosted",
		detail: "Runs on your laptop and your cloud",
		stackpanel: "yes",
		devenv: "yes",
		docker: "yes",
		paas: "no",
	},
];

const headers = [
	{
		key: "stackpanel" as const,
		title: "Stackpanel",
		emphasis: true,
		subtitle: "Open source",
	},
	{
		key: "devenv" as const,
		title: "Raw Nix / devenv",
		subtitle: "DIY",
	},
	{
		key: "docker" as const,
		title: "Docker Compose",
		subtitle: "Container-only",
	},
	{
		key: "paas" as const,
		title: "Hosted PaaS",
		subtitle: "Vercel · Render · Fly",
	},
];

function CellIcon({ value }: { value: Cell }) {
	if (value === "yes") {
		return (
			<span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-accent/15 text-accent">
				<Check className="h-4 w-4" />
			</span>
		);
	}
	if (value === "partial") {
		return (
			<span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-yellow-500/15 text-yellow-400">
				<Minus className="h-4 w-4" />
			</span>
		);
	}
	return (
		<span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-muted/30 text-muted-foreground/60">
			<X className="h-4 w-4" />
		</span>
	);
}

export function ComparisonSection() {
	return (
		<section className="border-border border-b" id="compare">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="text-center">
					<p className="font-medium text-accent text-sm">Comparison</p>
					<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
						Why not just use what we already have?
					</h2>
					<p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
						Each of these tools solves part of the problem. Stackpanel composes
						them — so you stop maintaining the glue.
					</p>
				</div>

				<div className="mt-12 overflow-hidden rounded-2xl border border-border bg-card">
					<div className="overflow-x-auto">
						<table className="w-full min-w-[720px] text-left">
							<thead className="border-border border-b bg-secondary/40">
								<tr>
									<th className="px-6 py-4 font-semibold text-foreground text-sm">
										Capability
									</th>
									{headers.map((header) => (
										<th
											className={`px-4 py-4 text-center font-semibold text-sm ${
												header.emphasis ? "text-foreground" : "text-foreground"
											}`}
											key={header.key}
										>
											<div
												className={`flex flex-col items-center gap-0.5 ${header.emphasis ? "text-accent" : ""}`}
											>
												<span>{header.title}</span>
												<span className="font-normal text-[11px] text-muted-foreground">
													{header.subtitle}
												</span>
											</div>
										</th>
									))}
								</tr>
							</thead>
							<tbody className="divide-y divide-border/60">
								{rows.map((row) => (
									<tr
										className="transition-colors hover:bg-secondary/20"
										key={row.feature}
									>
										<td className="px-6 py-4">
											<p className="font-medium text-foreground text-sm">
												{row.feature}
											</p>
											{row.detail ? (
												<p className="mt-0.5 text-muted-foreground text-xs">
													{row.detail}
												</p>
											) : null}
										</td>
										{headers.map((header) => (
											<td
												className={`px-4 py-4 text-center ${header.emphasis ? "bg-accent/[0.04]" : ""}`}
												key={`${row.feature}-${header.key}`}
											>
												<div className="flex justify-center">
													<CellIcon value={row[header.key]} />
												</div>
											</td>
										))}
									</tr>
								))}
							</tbody>
						</table>
					</div>
				</div>

				<p className="mt-6 text-center text-muted-foreground text-xs">
					Comparison reflects out-of-the-box behavior on a fresh repo. Most
					stacks can replicate parts of Stackpanel with enough custom tooling —
					that&apos;s the tooling we&apos;re replacing.
				</p>
			</div>
		</section>
	);
}
