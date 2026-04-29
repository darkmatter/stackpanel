import { createFileRoute, Link, redirect } from "@tanstack/react-router";
import { Button } from "@ui/button";
import {
	ArrowRight,
	BookOpen,
	Boxes,
	Github,
	KeyRound,
	MonitorPlay,
	Server,
} from "lucide-react";
import { getUser } from "@/functions/get-user";

export const Route = createFileRoute("/dashboard")({
	component: RouteComponent,
	beforeLoad: async () => {
		const session = await getUser();
		return { session };
	},
	loader: async ({ context }) => {
		if (!context.session) {
			throw redirect({ to: "/login" });
		}
	},
});

const quickActions = [
	{
		icon: MonitorPlay,
		title: "Open Studio",
		description: "Browse apps, services, secrets, and generated files.",
		to: "/studio",
		cta: "Launch Studio",
	},
	{
		icon: Server,
		title: "Pair an agent",
		description:
			"Connect this account to a local Stackpanel agent on your machine.",
		to: "/studio",
		cta: "Pair agent",
	},
	{
		icon: Boxes,
		title: "Browse extensions",
		description:
			"One-click install Postgres, Redis, MinIO, Caddy, and more.",
		to: "/studio",
		cta: "View registry",
	},
	{
		icon: KeyRound,
		title: "Manage team keys",
		description: "Add teammate AGE keys and rekey SOPS-encrypted secrets.",
		to: "/studio",
		cta: "Open secrets",
	},
];

const resources = [
	{
		icon: BookOpen,
		title: "Quick start",
		href: "/docs/quick-start",
		description: "Get a project running in under a minute.",
	},
	{
		icon: Github,
		title: "GitHub",
		href: "https://github.com/darkmatter/stackpanel",
		description: "Source code, issues, and discussions.",
		external: true,
	},
];

function RouteComponent() {
	const { session } = Route.useRouteContext();
	const name = session?.user.name?.split(" ")[0] ?? "there";

	return (
		<div className="min-h-screen bg-background">
			<div className="mx-auto max-w-6xl px-4 py-12 sm:px-6 lg:py-16">
				<div className="flex flex-col gap-2">
					<p className="font-medium text-accent text-sm">Welcome back</p>
					<h1 className="font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
						Hi {name} 👋
					</h1>
					<p className="max-w-xl text-muted-foreground">
						Your Stackpanel account is ready. Pair a local agent to start
						managing your dev environment, secrets, and services from one
						place.
					</p>
				</div>

				<div className="mt-10 grid gap-px overflow-hidden rounded-2xl border border-border bg-border sm:grid-cols-2">
					{quickActions.map((action) => (
						<div
							className="flex flex-col gap-3 bg-card p-6 transition-colors hover:bg-card/80"
							key={action.title}
						>
							<div className="flex h-11 w-11 items-center justify-center rounded-lg bg-accent/10 text-accent">
								<action.icon className="h-5 w-5" />
							</div>
							<div>
								<h2 className="font-semibold text-foreground text-lg">
									{action.title}
								</h2>
								<p className="mt-1 text-muted-foreground text-sm leading-relaxed">
									{action.description}
								</p>
							</div>
							<Button asChild className="mt-auto w-fit" size="sm">
								<Link to={action.to}>
									{action.cta}
									<ArrowRight className="ml-2 h-3.5 w-3.5" />
								</Link>
							</Button>
						</div>
					))}
				</div>

				<div className="mt-10 grid gap-4 sm:grid-cols-2">
					{resources.map((resource) =>
						resource.external ? (
							<a
								className="group flex items-start gap-4 rounded-xl border border-border bg-card p-5 transition-colors hover:border-accent/40"
								href={resource.href}
								key={resource.title}
								rel="noopener noreferrer"
								target="_blank"
							>
								<resource.icon className="mt-0.5 h-5 w-5 text-muted-foreground transition-colors group-hover:text-accent" />
								<div className="flex-1">
									<p className="font-medium text-foreground">
										{resource.title}
									</p>
									<p className="mt-1 text-muted-foreground text-sm">
										{resource.description}
									</p>
								</div>
								<ArrowRight className="mt-1 h-4 w-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
							</a>
						) : (
							<a
								className="group flex items-start gap-4 rounded-xl border border-border bg-card p-5 transition-colors hover:border-accent/40"
								href={resource.href}
								key={resource.title}
							>
								<resource.icon className="mt-0.5 h-5 w-5 text-muted-foreground transition-colors group-hover:text-accent" />
								<div className="flex-1">
									<p className="font-medium text-foreground">
										{resource.title}
									</p>
									<p className="mt-1 text-muted-foreground text-sm">
										{resource.description}
									</p>
								</div>
								<ArrowRight className="mt-1 h-4 w-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
							</a>
						),
					)}
				</div>
			</div>
		</div>
	);
}
