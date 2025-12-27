import { Link } from "@tanstack/react-router";
import { ArrowRight, Terminal } from "lucide-react";
import { Button } from "@/components/ui/button";

export function HeroSection() {
	return (
		<section className="relative overflow-hidden border-border border-b">
			<div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-accent/10 via-transparent to-transparent" />

			<div className="relative mx-auto max-w-7xl px-4 py-24 sm:px-6 sm:py-32 lg:px-8 lg:py-40">
				<div className="grid gap-12 lg:grid-cols-2 lg:gap-16">
					<div className="flex flex-col justify-center">
						<div className="mb-6 inline-flex w-fit items-center gap-2 rounded-full border border-border bg-secondary px-4 py-1.5">
							<span className="h-2 w-2 rounded-full bg-accent" />
							<span className="text-muted-foreground text-sm">
								The new localhost:3001
							</span>
						</div>

						<h1 className="text-balance font-bold text-4xl text-foreground tracking-tight sm:text-5xl lg:text-6xl">
							Build <span className="font-bold text-accent">products</span> not
							plumbing.
						</h1>

						<p className="mt-6 max-w-xl text-pretty text-lg text-muted-foreground leading-relaxed">
							From idea to production-ready app. StackPanel unifies
							infrastructure, tooling, secrets, and local development into one
							internal platform your whole team can access.
						</p>

						<div className="mt-8 flex flex-wrap gap-4">
							<Button
								asChild
								className="bg-foreground text-background hover:bg-foreground/90"
								size="lg"
							>
								<Link to="/demo">
									Get Started <ArrowRight className="ml-2 h-4 w-4" />
								</Link>
							</Button>
							<Button asChild size="lg" variant="outline">
								<Link to="/demo">Instant Demo</Link>
							</Button>
						</div>

						<div className="mt-8 flex items-center gap-6 text-muted-foreground text-sm">
							<div className="flex items-center gap-2">
								<span className="h-1.5 w-1.5 rounded-full bg-accent" />
								Self-hosted
							</div>
							<div className="flex items-center gap-2">
								<span className="h-1.5 w-1.5 rounded-full bg-accent" />
								Zero vendor lock-in
							</div>
							<div className="flex items-center gap-2">
								<span className="h-1.5 w-1.5 rounded-full bg-accent" />
								Cost-effective
							</div>
						</div>
					</div>

					<Link className="group relative block" to="/dashboard">
						<div className="overflow-hidden rounded-xl border border-border bg-card shadow-2xl transition-all group-hover:border-accent/50 group-hover:shadow-accent/10">
							<div className="flex items-center gap-2 border-border border-b bg-secondary/50 px-4 py-3">
								<div className="flex gap-1.5">
									<div className="h-3 w-3 rounded-full bg-red-500/80" />
									<div className="h-3 w-3 rounded-full bg-yellow-500/80" />
									<div className="h-3 w-3 rounded-full bg-green-500/80" />
								</div>
								<div className="flex-1 text-center">
									<span className="text-muted-foreground text-xs">
										stackpanel.internal
									</span>
								</div>
							</div>
							<div className="p-4">
								<div className="mb-4 flex items-center justify-between">
									<div className="flex items-center gap-3">
										<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/20">
											<Terminal className="h-5 w-5 text-accent" />
										</div>
										<div>
											<p className="font-medium text-foreground text-sm">
												acme-corp
											</p>
											<p className="text-muted-foreground text-xs">
												12 services · 8 team members
											</p>
										</div>
									</div>
									<span className="rounded-full bg-accent/20 px-2.5 py-1 text-accent text-xs">
										Active
									</span>
								</div>

								<div className="grid grid-cols-2 gap-3">
									{[
										{ label: "Infrastructure", count: "6 nodes" },
										{ label: "Databases", count: "3 active" },
										{ label: "Secrets", count: "24 keys" },
										{ label: "Dev Shells", count: "4 envs" },
									].map((item) => (
										<div
											className="rounded-lg border border-border bg-secondary/30 p-3"
											key={item.label}
										>
											<p className="text-muted-foreground text-xs">
												{item.label}
											</p>
											<p className="font-medium text-foreground text-sm">
												{item.count}
											</p>
										</div>
									))}
								</div>

								<div className="mt-4 rounded-lg bg-background p-3 font-mono text-xs">
									<div className="flex items-center gap-2 text-muted-foreground">
										<span className="text-accent">$</span>
										<span>create-app my-service --template=turborepo</span>
									</div>
									<div className="mt-2 text-accent">
										✓ Created repo acme-corp/my-service
									</div>
									<div className="text-accent">
										✓ Applied stack configuration
									</div>
									<div className="text-accent">✓ Enabled CI/CD pipeline</div>
								</div>
							</div>
						</div>
						<div className="absolute inset-0 flex items-center justify-center rounded-xl bg-background/80 opacity-0 transition-opacity group-hover:opacity-100">
							<span className="font-medium text-foreground text-lg">
								Click to try the demo
							</span>
						</div>
					</Link>
				</div>
			</div>
		</section>
	);
}
