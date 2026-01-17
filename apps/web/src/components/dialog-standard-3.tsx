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

export const title = "Scrollable with Sticky Header";

const Example = () => (
	<Dialog>
		<DialogTrigger render={<Button variant="outline" />}>
			View Changelog
		</DialogTrigger>
		<DialogContent className="p-0 sm:max-w-lg">
			<DialogHeader className="sticky top-0 z-10 border-b bg-background px-6 pt-6 pb-4">
				<DialogTitle>Changelog</DialogTitle>
				<DialogDescription>
					Recent updates and improvements to our platform.
				</DialogDescription>
			</DialogHeader>
			<ScrollArea className="h-[400px] px-6">
				<div className="space-y-6 py-4">
					<div>
						<h4 className="mb-2 font-semibold">Version 2.1.0 - March 2024</h4>
						<ul className="space-y-1 text-sm text-muted-foreground">
							<li>• Added dark mode support</li>
							<li>• Improved performance by 40%</li>
							<li>• Fixed critical security vulnerability</li>
							<li>• Updated dependencies to latest versions</li>
						</ul>
					</div>
					<div>
						<h4 className="mb-2 font-semibold">
							Version 2.0.0 - February 2024
						</h4>
						<ul className="space-y-1 text-sm text-muted-foreground">
							<li>• Complete UI redesign</li>
							<li>• New dashboard layout</li>
							<li>• Advanced analytics features</li>
							<li>• Mobile app improvements</li>
						</ul>
					</div>
					<div>
						<h4 className="mb-2 font-semibold">Version 1.9.0 - January 2024</h4>
						<ul className="space-y-1 text-sm text-muted-foreground">
							<li>• Added team collaboration features</li>
							<li>• Improved search functionality</li>
							<li>• Bug fixes and performance improvements</li>
							<li>• Enhanced accessibility</li>
						</ul>
					</div>
					<div>
						<h4 className="mb-2 font-semibold">
							Version 1.8.0 - December 2023
						</h4>
						<ul className="space-y-1 text-sm text-muted-foreground">
							<li>• New integration with third-party tools</li>
							<li>• Custom branding options</li>
							<li>• Improved export functionality</li>
							<li>• Performance optimizations</li>
						</ul>
					</div>
				</div>
			</ScrollArea>
			<DialogFooter className="px-6 pt-4 pb-6">
				<Button type="button">Close</Button>
			</DialogFooter>
		</DialogContent>
	</Dialog>
);

export default Example;
