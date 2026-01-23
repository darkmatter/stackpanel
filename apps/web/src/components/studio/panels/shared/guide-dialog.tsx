"use client";

import type { GuideEntry } from "@stackpanel/docs-content";
import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Button } from "@ui/button";
import {
	Dialog,
	DialogDescription,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
	DialogPortal,
	DialogClose,
} from "@ui/dialog";
import { ScrollArea } from "@ui/scroll-area";
import { Tooltip, TooltipContent, TooltipTrigger } from "@ui/tooltip";
import { Info, X, Minimize2, Square, Maximize2 } from "lucide-react";
import { useMemo, useState } from "react";
import { Response } from "@/components/response";
import { cn } from "@/lib/utils";

const contentClasses =
	"space-y-4 text-sm leading-relaxed text-foreground [&_h1]:text-xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:text-base [&_h3]:font-semibold [&_p]:text-muted-foreground [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5 [&_li]:text-muted-foreground [&_code]:rounded [&_code]:bg-muted [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-xs [&_a]:text-primary [&_a]:underline";

type DialogSize = "sm" | "md" | "lg";

const dialogSizes: Record<DialogSize, string> = {
	sm: "w-[380px] h-[380px]",
	md: "w-[520px] h-[520px]",
	lg: "w-[680px] h-[680px]",
};

const sizeIcons: Record<DialogSize, React.ReactNode> = {
	sm: <Minimize2 className="h-3.5 w-3.5" />,
	md: <Square className="h-3.5 w-3.5" />,
	lg: <Maximize2 className="h-3.5 w-3.5" />,
};

const sizeOrder: DialogSize[] = ["sm", "md", "lg"];

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
}

/**
 * A reusable floating dialog component for displaying guide/help content.
 * The dialog is pinned to the bottom-right corner and allows the user
 * to continue using the app while viewing help content.
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
}: GuideDialogProps) {
	const [dialogSize, setDialogSize] = useState<DialogSize>("md");

	// Strip frontmatter from the content
	const content = useMemo(
		() => stripFrontmatter(guide.content),
		[guide.content],
	);

	const cycleSize = () => {
		const currentIndex = sizeOrder.indexOf(dialogSize);
		const nextIndex = (currentIndex + 1) % sizeOrder.length;
		setDialogSize(sizeOrder[nextIndex]);
	};

	return (
		<Dialog modal={false}>
			<DialogTrigger className="inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 border border-input bg-background shadow-sm hover:bg-accent hover:text-accent-foreground h-8 px-3">
				{triggerContent ?? (
					<>
						<Info className="h-4 w-4" />
						Guide
					</>
				)}
			</DialogTrigger>
			<DialogPortal>
				<DialogPrimitive.Content
					data-slot="dialog-content"
					className={cn(
						"bg-background fixed bottom-4 right-4 z-50 flex flex-col rounded-lg border shadow-lg outline-none",
						dialogSizes[dialogSize],
						"data-[state=open]:animate-in data-[state=closed]:animate-out",
						"data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0",
						"data-[state=closed]:slide-out-to-right-4 data-[state=closed]:slide-out-to-bottom-4",
						"data-[state=open]:slide-in-from-right-4 data-[state=open]:slide-in-from-bottom-4",
						"duration-200"
					)}
					onPointerDownOutside={(e) => e.preventDefault()}
					onInteractOutside={(e) => e.preventDefault()}
				>
					<DialogHeader className="shrink-0 border-b bg-card px-4 pt-4 pb-3 rounded-t-lg">
						<div className="flex items-start justify-between gap-2">
							<div className="flex-1 min-w-0">
								<DialogTitle className="text-base">{guide.title}</DialogTitle>
								{guide.description && (
									<DialogDescription className="mt-1 text-xs">
										{guide.description}
									</DialogDescription>
								)}
							</div>
							<div className="flex items-center gap-1">
								<Tooltip>
									<TooltipTrigger asChild>
										<Button
											variant="ghost"
											size="icon"
											className="h-7 w-7 shrink-0 text-muted-foreground hover:text-foreground"
											onClick={cycleSize}
										>
											{sizeIcons[dialogSize]}
											<span className="sr-only">Toggle size</span>
										</Button>
									</TooltipTrigger>
									<TooltipContent side="bottom">Toggle size</TooltipContent>
								</Tooltip>
								<DialogClose asChild>
									<Button
										variant="ghost"
										size="icon"
										className="h-7 w-7 shrink-0 text-muted-foreground hover:text-foreground"
									>
										<X className="h-4 w-4" />
										<span className="sr-only">Close</span>
									</Button>
								</DialogClose>
							</div>
						</div>
					</DialogHeader>
					<div className="flex-1 overflow-hidden">
						<ScrollArea className="h-full">
							<div className="px-4 py-4">
								<div className={contentClasses}>
									<Response>{content}</Response>
								</div>
							</div>
						</ScrollArea>
					</div>
				</DialogPrimitive.Content>
			</DialogPortal>
		</Dialog>
	);
}
