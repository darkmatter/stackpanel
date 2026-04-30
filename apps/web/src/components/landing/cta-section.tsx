import { Link } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { ArrowRight, BookOpen, Github, MonitorPlay } from "lucide-react";
import { useWaitlist } from "./waitlist-dialog";

export function CTASection() {
	const waitlist = useWaitlist();
	return (
		<section className="border-border border-b">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="relative overflow-hidden rounded-3xl border border-border bg-card">
					<div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-accent/15 via-transparent to-transparent" />
					<div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-accent/40 to-transparent" />

					<div className="relative px-6 py-16 text-center sm:px-12 sm:py-24">
						<div className="mx-auto inline-flex items-center gap-2 rounded-full border border-border bg-background/60 px-4 py-1.5 text-muted-foreground text-xs">
							<span className="h-1.5 w-1.5 rounded-full bg-accent" />
							Private beta · Open source core (MIT)
						</div>

						<h2 className="mt-6 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-5xl">
							Reserve your spot in the beta.
						</h2>
						<p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground sm:text-lg">
							Stackpanel core ships free for everyone. Production Stacks land
							as managed subscriptions on top. Join the beta to get early
							access to both, plus a direct line to the team building it.
						</p>

						<div className="mt-8 flex flex-wrap items-center justify-center gap-3">
							<Button
								className="bg-foreground text-background hover:bg-foreground/90"
								size="lg"
								onClick={() => waitlist.open({ source: "landing.cta" })}
							>
								Join the beta waitlist
								<ArrowRight className="ml-2 h-4 w-4" />
							</Button>
							<Button asChild size="lg" variant="outline">
								<Link to="/demo">
									<MonitorPlay className="mr-2 h-4 w-4" />
									Try the demo
								</Link>
							</Button>
							<Button
								asChild
								className="text-muted-foreground hover:text-foreground"
								size="lg"
								variant="ghost"
							>
								<a
									href="https://github.com/darkmatter/stackpanel"
									rel="noopener noreferrer"
									target="_blank"
								>
									<Github className="mr-2 h-4 w-4" />
									GitHub
								</a>
							</Button>
						</div>

						<div className="mx-auto mt-10 grid max-w-xl gap-3 text-left text-sm sm:grid-cols-3">
							<div className="rounded-xl border border-border bg-background/40 p-3">
								<p className="font-mono text-[11px] text-muted-foreground">
									Step 1
								</p>
								<p className="mt-1 font-mono text-foreground text-xs">
									nix flake init -t …
								</p>
							</div>
							<div className="rounded-xl border border-border bg-background/40 p-3">
								<p className="font-mono text-[11px] text-muted-foreground">
									Step 2
								</p>
								<p className="mt-1 font-mono text-foreground text-xs">
									direnv allow
								</p>
							</div>
							<div className="rounded-xl border border-border bg-background/40 p-3">
								<p className="font-mono text-[11px] text-muted-foreground">
									Step 3
								</p>
								<p className="mt-1 font-mono text-foreground text-xs">dev</p>
							</div>
						</div>

						<p className="mt-8 inline-flex items-center gap-2 text-muted-foreground text-xs">
							<BookOpen className="h-3.5 w-3.5" />
							Prefer to read first?{" "}
							<a
								className="text-foreground underline underline-offset-4 hover:text-accent"
								href="/docs"
							>
								Browse the docs
							</a>
						</p>
					</div>
				</div>
			</div>
		</section>
	);
}
