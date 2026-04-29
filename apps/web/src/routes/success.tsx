import { createFileRoute, Link, useSearch } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { ArrowRight, CheckCircle2, MonitorPlay } from "lucide-react";

export const Route = createFileRoute("/success")({
	component: SuccessPage,
	validateSearch: (search) => ({
		checkout_id: search.checkout_id as string,
	}),
});

function SuccessPage() {
	const { checkout_id } = useSearch({ from: "/success" });

	return (
		<div className="flex min-h-screen items-center justify-center bg-background px-4 py-16">
			<div className="w-full max-w-xl rounded-2xl border border-border bg-card p-8 text-center sm:p-12">
				<div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-accent/15 text-accent">
					<CheckCircle2 className="h-7 w-7" />
				</div>
				<h1 className="mt-6 font-bold font-[Montserrat] text-2xl text-foreground sm:text-3xl">
					You&apos;re all set.
				</h1>
				<p className="mt-3 text-muted-foreground">
					Thanks for upgrading. Your account now has access to the full
					Stackpanel experience.
				</p>

				{checkout_id ? (
					<p className="mx-auto mt-4 max-w-md break-all rounded-md bg-secondary/50 px-3 py-2 font-mono text-muted-foreground text-xs">
						Receipt: {checkout_id}
					</p>
				) : null}

				<div className="mt-8 flex flex-wrap justify-center gap-3">
					<Button
						asChild
						className="bg-foreground text-background hover:bg-foreground/90"
					>
						<Link to="/dashboard">
							Go to dashboard
							<ArrowRight className="ml-2 h-4 w-4" />
						</Link>
					</Button>
					<Button asChild variant="outline">
						<Link to="/studio">
							<MonitorPlay className="mr-2 h-4 w-4" />
							Open Studio
						</Link>
					</Button>
				</div>
			</div>
		</div>
	);
}
