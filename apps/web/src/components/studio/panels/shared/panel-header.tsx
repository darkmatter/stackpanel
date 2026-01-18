"use client";

import type * as React from "react";
import { cn } from "@/lib/utils";
import { type guides, HelpButton } from "./help-button";

interface PanelHeaderProps extends React.ComponentProps<"div"> {
	/** Panel title */
	title: string;
	/** Description text shown below the title */
	description?: string;
	/** Guide key for the help button */
	guideKey?: keyof typeof guides;
	/** Tooltip text for the help button */
	helpTooltip?: string;
	/** Action buttons or other elements shown on the right side */
	actions?: React.ReactNode;
	/** Size variant */
	size?: "default" | "lg";
}

/**
 * Consistent panel header with title, description, help button, and actions.
 *
 * @example
 * ```tsx
 * <PanelHeader
 *   title="Variables & Secrets"
 *   description="Manage environment variables and secrets"
 *   guideKey="variables"
 *   actions={<Button>Add Variable</Button>}
 * />
 * ```
 */
function PanelHeader({
	title,
	description,
	guideKey,
	helpTooltip,
	actions,
	size = "default",
	className,
	...props
}: PanelHeaderProps) {
	const titleSize = size === "lg" ? "text-2xl" : "text-xl";

	return (
		<div
			className={cn("flex items-center justify-between", className)}
			{...props}
		>
			<div>
				<h2
					className={cn(
						"font-semibold text-foreground flex items-center gap-2",
						titleSize,
					)}
				>
					{title}
					{guideKey && (
						<HelpButton
							guideKey={guideKey}
							tooltip={helpTooltip || `Learn about ${title.toLowerCase()}`}
						/>
					)}
				</h2>
				{description && (
					<p className="text-muted-foreground text-sm">{description}</p>
				)}
			</div>
			{actions && <div className="flex items-center gap-2">{actions}</div>}
		</div>
	);
}

export { PanelHeader };
export type { PanelHeaderProps };
