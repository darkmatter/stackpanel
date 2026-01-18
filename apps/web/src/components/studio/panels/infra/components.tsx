/**
 * Shared UI components for the infrastructure panel.
 */
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import { Copy, ExternalLink, Server } from "lucide-react";
import type { SSTResource } from "./types";

/** Status indicator card for displaying a metric */
export function StatusCard({
	icon: Icon,
	label,
	value,
	active,
}: {
	icon: React.ElementType;
	label: string;
	value: string;
	active: boolean;
}) {
	return (
		<Card>
			<CardContent className="p-4">
				<div className="flex items-center gap-3">
					<div
						className={`flex h-10 w-10 items-center justify-center rounded-lg ${
							active ? "bg-accent/10" : "bg-muted"
						}`}
					>
						<Icon
							className={`h-5 w-5 ${
								active ? "text-accent" : "text-muted-foreground"
							}`}
						/>
					</div>
					<div>
						<p className="font-bold text-2xl text-foreground">{value}</p>
						<p className="text-muted-foreground text-sm">{label}</p>
					</div>
				</div>
			</CardContent>
		</Card>
	);
}

/** Resource row for displaying a deployed AWS resource */
export function ResourceRow({ resource }: { resource: SSTResource }) {
	return (
		<div className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3">
			<div className="flex items-center gap-3">
				<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
					<Server className="h-5 w-5 text-muted-foreground" />
				</div>
				<div>
					<p className="font-medium text-foreground text-sm">{resource.type}</p>
					<code className="text-muted-foreground text-xs">
						{resource.id || resource.urn}
					</code>
				</div>
			</div>
			<Badge variant="outline" className="text-xs">
				{resource.type?.split("::")[1] || "Resource"}
			</Badge>
		</div>
	);
}

/** Output row for displaying a stack output value */
export function OutputRow({
	name,
	value,
	onCopy,
}: {
	name: string;
	value: unknown;
	onCopy: (text: string) => void;
}) {
	const stringValue =
		typeof value === "string" ? value : JSON.stringify(value as object);

	return (
		<div className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3">
			<div className="min-w-0 flex-1">
				<p className="font-medium text-foreground text-sm">{name}</p>
				<code className="text-muted-foreground text-xs truncate block">
					{stringValue}
				</code>
			</div>
			<div className="flex items-center gap-2 ml-4">
				<Button
					size="icon"
					variant="ghost"
					className="h-8 w-8"
					onClick={() => onCopy(stringValue)}
				>
					<Copy className="h-4 w-4" />
				</Button>
				{typeof value === "string" && value.startsWith("arn:") && (
					<Button size="icon" variant="ghost" className="h-8 w-8" asChild>
						<a
							href="https://console.aws.amazon.com/"
							target="_blank"
							rel="noopener noreferrer"
						>
							<ExternalLink className="h-4 w-4" />
						</a>
					</Button>
				)}
			</div>
		</div>
	);
}
