"use client";

import { Button } from "@ui/button";
import { ArrowRight, LogOut, Sparkles } from "lucide-react";
import { useWaitlist } from "@/components/landing/waitlist-dialog";
import { useAgentEndpoint } from "@/lib/agent-endpoint";

/**
 * Persistent banner shown above the studio header whenever the active agent
 * endpoint is the in-browser MSW mock. Communicates the limitations of demo
 * mode (no real execution, fixture data) and offers two escape hatches:
 * sign up for the beta, or switch back to the local agent.
 */
export function DemoBanner() {
	const waitlist = useWaitlist();
	const { useLocal } = useAgentEndpoint();

	return (
		<div className="border-b border-amber-500/30 bg-amber-500/[0.06]">
			<div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-2.5 text-xs sm:px-6">
				<div className="flex min-w-0 items-center gap-2 text-amber-200">
					<Sparkles className="h-3.5 w-3.5 shrink-0 text-amber-400" />
					<span className="truncate">
						<span className="font-semibold text-amber-100">Demo mode.</span>{" "}
						You're running the real Studio against fixture data. Writes are
						no-ops; install the CLI to use a live local agent.
					</span>
				</div>
				<div className="flex items-center gap-1">
					<Button
						size="sm"
						variant="ghost"
						className="h-7 px-2 text-xs text-amber-100 hover:bg-amber-500/15 hover:text-amber-50"
						onClick={() => waitlist.open({ source: "demo.banner" })}
					>
						Join the beta
						<ArrowRight className="ml-1 h-3 w-3" />
					</Button>
					<Button
						size="sm"
						variant="ghost"
						className="h-7 px-2 text-xs text-amber-200 hover:bg-amber-500/15 hover:text-amber-50"
						onClick={() => useLocal()}
						aria-label="Exit demo mode"
					>
						<LogOut className="mr-1 h-3 w-3" />
						Exit demo
					</Button>
				</div>
			</div>
		</div>
	);
}
