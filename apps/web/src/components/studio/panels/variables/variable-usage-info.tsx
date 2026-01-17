"use client";

import { Badge } from "@ui/badge";
import { useAppsWithVariable } from "@/lib/use-nix-config";

interface VariableUsageInfoProps {
	variableId: string;
}

export function VariableUsageInfo({ variableId }: VariableUsageInfoProps) {
	const { data: apps, isLoading } = useAppsWithVariable(variableId);

	if (isLoading) {
		return <span className="text-muted-foreground text-xs">Loading...</span>;
	}

	if (!apps || apps.length === 0) {
		return (
			<span className="text-muted-foreground text-xs">Not used by any app</span>
		);
	}

	return (
		<div className="flex flex-wrap gap-1">
			{apps.map((app) => (
				<Badge key={app.id} variant="outline" className="text-xs">
					{app.name}
				</Badge>
			))}
		</div>
	);
}
