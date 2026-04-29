"use client";

import { Link } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { SidebarTrigger } from "@ui/sidebar";
import { CheckCircle2, ExternalLink, GitBranch, Home } from "lucide-react";
import { useWaitlist } from "@/components/landing/waitlist-dialog";
import { DEMO_PROJECT } from "./demo-fixtures";

export function DemoHeader() {
	const waitlist = useWaitlist();

	return (
		<header className="flex h-14 shrink-0 items-center gap-3 border-b border-border bg-background/60 px-4 backdrop-blur">
			<SidebarTrigger className="-ml-1" />

			<div className="flex min-w-0 flex-1 items-center gap-3">
				<div className="flex items-center gap-2">
					<div className="flex h-7 w-7 items-center justify-center rounded-md bg-accent/15 text-accent">
						<Home className="h-3.5 w-3.5" />
					</div>
					<div className="min-w-0">
						<p className="truncate font-mono text-foreground text-sm">
							{DEMO_PROJECT.name}
						</p>
						<p className="truncate text-[11px] text-muted-foreground">
							{DEMO_PROJECT.root}
						</p>
					</div>
				</div>

				<Badge
					variant="outline"
					className="hidden gap-1 border-border/60 bg-card/40 font-mono text-[10px] text-muted-foreground sm:inline-flex"
				>
					<GitBranch className="h-3 w-3" />
					{DEMO_PROJECT.branch}
				</Badge>

				<Badge
					variant="outline"
					className="hidden gap-1 border-emerald-500/30 bg-emerald-500/10 text-[10px] text-emerald-300 sm:inline-flex"
				>
					<CheckCircle2 className="h-3 w-3" />
					Devshell entered
				</Badge>
			</div>

			<div className="flex items-center gap-2">
				<Button
					asChild
					variant="ghost"
					size="sm"
					className="hidden text-muted-foreground hover:text-foreground sm:inline-flex"
				>
					<Link to="/">
						<ExternalLink className="mr-1 h-3 w-3" />
						Back to site
					</Link>
				</Button>
				<Button
					size="sm"
					className="bg-foreground text-background hover:bg-foreground/90"
					onClick={() => waitlist.open({ source: "demo.header" })}
				>
					Join the beta
				</Button>
			</div>
		</header>
	);
}
