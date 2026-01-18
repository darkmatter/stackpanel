"use client";

import { type GuideEntry, guides } from "@stackpanel/docs-content";
import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@ui/dialog";
import { ScrollArea } from "@ui/scroll-area";
import { Tooltip, TooltipContent, TooltipTrigger } from "@ui/tooltip";
import { HelpCircle } from "lucide-react";
import { useMemo } from "react";
import { Response } from "@/components/response";

const contentClasses =
	"space-y-4 text-sm leading-relaxed text-foreground [&_h1]:text-xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:text-base [&_h3]:font-semibold [&_p]:text-muted-foreground [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5 [&_li]:text-muted-foreground [&_code]:rounded [&_code]:bg-muted [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-xs [&_a]:text-primary [&_a]:underline [&_table]:w-full [&_table]:text-sm [&_th]:text-left [&_th]:font-medium [&_th]:p-2 [&_th]:border-b [&_td]:p-2 [&_td]:border-b [&_td]:text-muted-foreground";

/**
 * Strips YAML frontmatter from MDX content.
 * Frontmatter is delimited by --- at the start and end.
 */
function stripFrontmatter(content: string): string {
	const frontmatterRegex = /^---\s*\n[\s\S]*?\n---\s*\n/;
	return content.replace(frontmatterRegex, "").trim();
}

interface HelpButtonProps {
	/** The guide key from the guides object */
	guideKey: keyof typeof guides;
	/** Optional tooltip text */
	tooltip?: string;
	/** Optional size variant */
	size?: "sm" | "default";
}

/**
 * A compact help button that opens a guide dialog.
 * Use this in panel headers and sections where help content is available.
 *
 * @example
 * ```tsx
 * <HelpButton guideKey="variables" />
 * <HelpButton guideKey="secrets" tooltip="Learn about encryption" />
 * ```
 */
export function HelpButton({
	guideKey,
	tooltip = "Help",
	size = "sm",
}: HelpButtonProps) {
	const guide = guides[guideKey];

	// Strip frontmatter from the content
	const content = useMemo(
		() => (guide ? stripFrontmatter(guide.content) : ""),
		[guide],
	);

	if (!guide) {
		console.warn(`Guide "${guideKey}" not found`);
		return null;
	}

	return (
		<Dialog>
			<Tooltip>
				<TooltipTrigger asChild>
					<DialogTrigger asChild>
						<Button
							variant="ghost"
							size={size === "sm" ? "icon" : "default"}
							className={
								size === "sm"
									? "h-7 w-7 text-muted-foreground hover:text-foreground"
									: "gap-2"
							}
						>
							<HelpCircle className={size === "sm" ? "h-4 w-4" : "h-4 w-4"} />
							{size !== "sm" && <span>Help</span>}
						</Button>
					</DialogTrigger>
				</TooltipTrigger>
				<TooltipContent side="bottom">{tooltip}</TooltipContent>
			</Tooltip>
			<DialogContent className="p-0 sm:max-w-lg">
				<DialogHeader className="sticky top-0 z-10 border-b bg-background px-6 pt-6 pb-4">
					<DialogTitle>{guide.title}</DialogTitle>
					{guide.description && (
						<DialogDescription>{guide.description}</DialogDescription>
					)}
				</DialogHeader>
				<ScrollArea className="max-h-[60vh] px-6">
					<div className="space-y-6 py-4">
						<div className={contentClasses}>
							<Response>{content}</Response>
						</div>
					</div>
				</ScrollArea>
			</DialogContent>
		</Dialog>
	);
}

// Re-export guides for convenience
export { guides };
export type { GuideEntry };
