"use client";

import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
} from "@ui/card";
import {
	CheckCircle2,
	ChevronRight,
	Circle,
	Clock,
	Loader2,
	Lock,
} from "lucide-react";
import { StatusBadge, type StatusConfig } from "@/components/ui/status-badge";
import { cn } from "@/lib/utils";
import type { SetupStep, StepStatus } from "./types";

// =============================================================================
// Step Status Badge
// =============================================================================

const stepStatusConfig: Record<StepStatus, StatusConfig> = {
	complete: { icon: CheckCircle2, text: "Complete", variant: "success" },
	incomplete: { icon: Circle, text: "Not configured", variant: "muted" },
	"in-progress": { icon: Loader2, text: "In progress", variant: "info" },
	optional: { icon: Clock, text: "Optional", variant: "warning" },
	blocked: { icon: Lock, text: "Requires previous step", variant: "muted" },
};

function StepStatusBadge({ status }: { status: StepStatus }) {
	return <StatusBadge status={stepStatusConfig[status]} />;
}

// =============================================================================
// Step Card
// =============================================================================

interface StepCardProps {
	step: SetupStep;
	isExpanded: boolean;
	onToggle: () => void;
	children: React.ReactNode;
}

export function StepCard({
	step,
	isExpanded,
	onToggle,
	children,
}: StepCardProps) {
	const isBlocked = step.status === "blocked";

	return (
		<Card
			className={cn(
				"transition-all",
				isBlocked && "opacity-50 cursor-not-allowed",
				!isBlocked && "cursor-pointer hover:border-accent/50",
				isExpanded && "border-accent",
			)}
		>
			<CardHeader
				className={cn("pb-3", !isBlocked && "cursor-pointer")}
				onClick={() => !isBlocked && onToggle()}
			>
				<div className="flex items-center justify-between">
					<div className="flex items-center gap-4">
						<div
							className={cn(
								"flex items-center justify-center w-10 h-10 rounded-full",
								step.status === "complete"
									? "bg-emerald-600/20 text-emerald-500"
									: "bg-muted text-muted-foreground",
							)}
						>
							{step.icon}
						</div>
						<div>
							<CardTitle className="text-base flex items-center gap-2">
								{step.title}
								{!step.required && (
									<span className="text-xs font-normal text-muted-foreground">
										(optional)
									</span>
								)}
							</CardTitle>
							<CardDescription className="text-sm">
								{step.description}
							</CardDescription>
						</div>
					</div>
					<div className="flex items-center gap-3">
						<StepStatusBadge status={step.status} />
						<ChevronRight
							className={cn(
								"h-5 w-5 text-muted-foreground transition-transform",
								isExpanded && "rotate-90",
							)}
						/>
					</div>
				</div>
			</CardHeader>
			{isExpanded && (
				<CardContent className="pt-0 border-t">
					<div className="pt-4">{children}</div>
				</CardContent>
			)}
		</Card>
	);
}
