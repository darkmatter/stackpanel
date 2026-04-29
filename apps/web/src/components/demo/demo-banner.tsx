"use client";

import { Button } from "@ui/button";
import { ArrowRight, Sparkles, X } from "lucide-react";
import { useState } from "react";
import { useWaitlist } from "@/components/landing/waitlist-dialog";

export function DemoBanner() {
	const [dismissed, setDismissed] = useState(false);
	const waitlist = useWaitlist();

	if (dismissed) return null;

	return (
		<div className="border-b border-amber-500/30 bg-amber-500/[0.06]">
			<div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-2.5 text-xs sm:px-6">
				<div className="flex min-w-0 items-center gap-2 text-amber-200">
					<Sparkles className="h-3.5 w-3.5 shrink-0 text-amber-400" />
					<span className="truncate">
						<span className="font-semibold text-amber-100">Demo mode.</span>{" "}
						Realistic fixture data. Actions are no-ops. Pair a real local
						agent to use the actual Studio.
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
						className="h-7 w-7 p-0 text-amber-200 hover:bg-amber-500/15 hover:text-amber-50"
						aria-label="Dismiss"
						onClick={() => setDismissed(true)}
					>
						<X className="h-3.5 w-3.5" />
					</Button>
				</div>
			</div>
		</div>
	);
}
