import { createFileRoute } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import { Input } from "@ui/input";
import {
	Eye,
	EyeOff,
	KeyRound,
	Lock,
	Search,
	ShieldCheck,
	Variable,
} from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import {
	DEMO_PROJECT,
	DEMO_VARIABLES,
} from "@/components/demo/demo-fixtures";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/demo/variables")({
	component: DemoVariablesPage,
});

function DemoVariablesPage() {
	const [reveal, setReveal] = useState(false);
	const [filter, setFilter] = useState("");
	const visible = useMemo(() => {
		if (!filter.trim()) return DEMO_VARIABLES;
		const q = filter.trim().toLowerCase();
		return DEMO_VARIABLES.filter(
			(v) =>
				v.key.toLowerCase().includes(q) ||
				(v.app ?? "").toLowerCase().includes(q),
		);
	}, [filter]);

	return (
		<div className="mx-auto max-w-7xl space-y-6 p-6">
			<div className="flex flex-wrap items-start justify-between gap-3">
				<div className="space-y-1">
					<p className="text-xs uppercase tracking-[0.16em] text-muted-foreground">
						Variables &amp; secrets
					</p>
					<h1 className="font-bold font-[Montserrat] text-3xl text-foreground tracking-tight">
						SOPS-encrypted, AGE-recipient based
					</h1>
					<p className="text-muted-foreground text-sm">
						Edit per environment. Stackpanel re-keys files for every team
						member, syncs them to Cloudflare / Fly / Workers, and ships a
						type-safe <span className="font-mono">@gen/env</span> package to
						each app.
					</p>
				</div>

				<div className="flex items-center gap-2">
					<div className="relative">
						<Search className="-translate-y-1/2 absolute top-1/2 left-2.5 h-3.5 w-3.5 text-muted-foreground" />
						<Input
							value={filter}
							onChange={(e) => setFilter(e.target.value)}
							placeholder="Filter…"
							className="h-8 w-44 pl-7 text-xs"
						/>
					</div>
					<Button
						variant="outline"
						size="sm"
						onClick={() => setReveal((r) => !r)}
					>
						{reveal ? (
							<>
								<EyeOff className="mr-1 h-3.5 w-3.5" /> Hide values
							</>
						) : (
							<>
								<Eye className="mr-1 h-3.5 w-3.5" /> Reveal values
							</>
						)}
					</Button>
				</div>
			</div>

			<Card className="overflow-hidden">
				<CardContent className="p-0">
					<table className="w-full text-sm">
						<thead className="border-b border-border/60 bg-muted/30 text-left text-[11px] uppercase tracking-[0.12em] text-muted-foreground">
							<tr>
								<th className="px-4 py-2 font-medium">Key</th>
								<th className="hidden px-4 py-2 font-medium md:table-cell">
									Scope
								</th>
								<th className="px-4 py-2 font-medium">dev</th>
								<th className="hidden px-4 py-2 font-medium md:table-cell">
									staging
								</th>
								<th className="px-4 py-2 font-medium">prod</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-border/40">
							{visible.map((v) => (
								<tr key={v.key} className="hover:bg-muted/20">
									<td className="px-4 py-3">
										<div className="flex items-center gap-2">
											<KeyRound className="h-3 w-3 text-muted-foreground" />
											<span className="font-mono text-xs text-foreground">
												{v.key}
											</span>
											{v.encrypted ? (
												<Badge
													variant="outline"
													className="gap-1 border-border/60 px-1.5 py-0 text-[10px] font-normal text-muted-foreground"
												>
													<Lock className="h-2.5 w-2.5" />
													SOPS
												</Badge>
											) : null}
										</div>
									</td>
									<td className="hidden px-4 py-3 md:table-cell">
										<Badge
											variant="outline"
											className={cn(
												"px-1.5 py-0 text-[10px] font-normal",
												v.scope === "shared"
													? "border-border/60 text-muted-foreground"
													: "border-accent/30 bg-accent/10 text-accent",
											)}
										>
											{v.scope === "shared" ? "shared" : v.app}
										</Badge>
									</td>
									<td className="px-4 py-3 font-mono text-[11px]">
										<ValueCell value={v.dev} reveal={reveal} encrypted={v.encrypted} />
									</td>
									<td className="hidden px-4 py-3 font-mono text-[11px] md:table-cell">
										<ValueCell
											value={v.staging}
											reveal={reveal}
											encrypted={v.encrypted}
										/>
									</td>
									<td className="px-4 py-3 font-mono text-[11px]">
										<ValueCell value={v.prod} reveal={reveal} encrypted={v.encrypted} />
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
								{DEMO_PROJECT.team.length} AGE recipients with access
							</p>
							<p className="text-xs text-muted-foreground">
								Adding a teammate auto-rekeys every encrypted file. Removing
								one rotates the affected secrets.
							</p>
						</div>
					</div>
					<div className="flex flex-wrap gap-2">
						{DEMO_PROJECT.team.map((member) => (
							<Badge
								key={member.email}
								variant="outline"
								className="gap-1.5 border-border/60 bg-card/40 px-2 py-1 text-xs font-normal text-muted-foreground"
							>
								<span className="flex h-4 w-4 items-center justify-center rounded-full bg-accent/15 text-[10px] font-medium text-accent">
									{member.name
										.split(" ")
										.map((part) => part[0])
										.join("")}
								</span>
								<span className="text-foreground">{member.name}</span>
								<span className="text-muted-foreground/70">
									· {member.role}
								</span>
							</Badge>
						))}
						<Button
							size="sm"
							variant="outline"
							className="h-7 text-xs"
							onClick={() =>
								toast.info(
									"Demo mode — invite syncs AGE recipients in the live Studio.",
								)
							}
						>
							<Variable className="mr-1 h-3 w-3" /> Invite
						</Button>
					</div>
				</CardContent>
			</Card>
		</div>
	);
}

function ValueCell({
	value,
	reveal,
	encrypted,
}: {
	value: string;
	reveal: boolean;
	encrypted?: boolean;
}) {
	if (encrypted && !reveal) {
		return (
			<span className="text-muted-foreground tracking-widest">••••••••</span>
		);
	}
	return <span className="text-foreground">{value}</span>;
}
