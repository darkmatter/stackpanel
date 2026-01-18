"use client";

import type { GuideEntry } from "@stackpanel/docs-content";
import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@ui/dialog";
import { ScrollArea } from "@ui/scroll-area";
import { Info } from "lucide-react";
import { useMemo } from "react";
import { Response } from "@/components/response";

const contentClasses =
	"space-y-4 text-sm leading-relaxed text-foreground [&_h1]:text-xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:text-base [&_h3]:font-semibold [&_p]:text-muted-foreground [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5 [&_li]:text-muted-foreground [&_code]:rounded [&_code]:bg-muted [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-xs [&_a]:text-primary [&_a]:underline";

/**
 * Strips YAML frontmatter from MDX content.
 * Frontmatter is delimited by --- at the start and end.
 */
function stripFrontmatter(content: string): string {
	const frontmatterRegex = /^---\s*\n[\s\S]*?\n---\s*\n/;
	return content.replace(frontmatterRegex, "").trim();
}

interface GuideDialogProps {
	/** The guide content to display */
	guide: GuideEntry;
	/** Optional custom trigger content. Defaults to an "Info" icon with "Guide" label */
	triggerContent?: React.ReactNode;
	/** Optional max width class for the dialog. Defaults to "sm:max-w-lg" */
	maxWidth?: string;
}

/**
 * A reusable dialog component for displaying guide/help content.
 * Can be used with any guide entry from @stackpanel/docs-content.
 *
 * @example
 * ```tsx
 * import { guides } from "@stackpanel/docs-content";
 *
 * <GuideDialog guide={guides.variables} />
 * ```
 */
export function GuideDialog({
	guide,
	triggerContent,
	maxWidth = "sm:max-w-lg",
}: GuideDialogProps) {
	// Strip frontmatter from the content
	const content = useMemo(
		() => stripFrontmatter(guide.content),
		[guide.content],
	);

	return (
		<Dialog>
			<DialogTrigger className="inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 border border-input bg-background shadow-sm hover:bg-accent hover:text-accent-foreground h-8 px-3">
				{triggerContent ?? (
					<>
						<Info className="h-4 w-4" />
						Guide
					</>
				)}
			</DialogTrigger>
			<DialogContent className={`p-0 rounded-lg ${maxWidth}`}>
				<DialogHeader className="sticky top-0 z-10 border-b bg-background px-6 pt-6 pb-4">
					<DialogTitle>{guide.title}</DialogTitle>
					{guide.description && (
						<DialogDescription>{guide.description}</DialogDescription>
					)}
				</DialogHeader>
				<ScrollArea className="h-100 px-6">
					<div className="space-y-6 py-4">
						<div className={contentClasses}>
							<Response>{content}</Response>
						</div>
					</div>
				</ScrollArea>
				<DialogFooter className="px-6 pt-4 pb-6">
					<Button type="button">Close</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
