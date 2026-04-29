import { Link } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { ArrowRight, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { useWaitlist } from "./waitlist-dialog";

type CTA =
	| { label: string; kind: "waitlist"; tier: string }
	| { label: string; kind: "link"; to: string }
	| { label: string; kind: "email"; href: string };

type Tier = {
	id: string;
	name: string;
	tagline: string;
	price: string;
	priceDetail: string;
	highlight?: boolean;
	cta: CTA;
	bullets: string[];
};

const tiers: Tier[] = [
	{
		id: "community",
		name: "Community",
		tagline: "Solo dev. Free forever.",
		price: "$0",
		priceDetail: "1 seat · no card required",
		cta: { label: "Join the waitlist", kind: "waitlist", tier: "community" },
		bullets: [
			"Stackpanel core (MIT)",
			"All 3 stacks on community branch",
			"Best-effort patches",
			"GitHub Discussions support",
		],
	},
	{
		id: "team",
		name: "Team",
		tagline: "For shipping teams.",
		price: "$19",
		priceDetail: "per user / month, billed monthly",
		highlight: true,
		cta: { label: "Request beta access", kind: "waitlist", tier: "team" },
		bullets: [
			"Everything in Community",
			"Stable branch of every Production Stack",
			"30-day patch SLA",
			"Email support, next business day",
		],
	},
	{
		id: "business",
		name: "Business",
		tagline: "For platform teams.",
		price: "$49",
		priceDetail: "per user / month, billed monthly",
		cta: { label: "Request beta access", kind: "waitlist", tier: "business" },
		bullets: [
			"Everything in Team",
			"7-day patch SLA + early access channel",
			"Multi-org, SSO, audit logs",
			"Discord channel + 4-hour email response",
		],
	},
	{
		id: "enterprise",
		name: "Enterprise",
		tagline: "For companies that ship the world.",
		price: "Custom",
		priceDetail: "from $5,000 / month",
		cta: { label: "Talk to us", kind: "email", href: "mailto:sales@stackpanel.dev" },
		bullets: [
			"24-hour critical CVE SLA",
			"Air-gapped mirror license",
			"Slack channel, on-call, named CSM",
			"Indemnification, SCIM, custom RBAC",
		],
	},
];

export function PricingSection() {
	const waitlist = useWaitlist();
	return (
		<section className="border-border border-b" id="pricing">
			<div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
				<div className="text-center">
					<p className="font-medium text-accent text-sm">Pricing</p>
					<h2 className="mt-4 text-balance font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
						Free dev environment. Paid production support.
					</h2>
					<p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
						The Stackpanel core is MIT and free forever. Subscribe when
						you&apos;re ready to outsource the maintenance of your production
						deploys to a team that does it full-time.
					</p>
				</div>

				<div className="mt-14 grid gap-px overflow-hidden rounded-2xl border border-border bg-border lg:grid-cols-4">
					{tiers.map((tier) => (
						<div
							className={cn(
								"flex flex-col gap-6 p-6 transition-colors",
								tier.highlight
									? "bg-accent/[0.06] hover:bg-accent/[0.09]"
									: "bg-card hover:bg-card/80",
							)}
							key={tier.id}
						>
							<div>
								<div className="flex items-center justify-between">
									<h3 className="font-semibold text-foreground text-lg">
										{tier.name}
									</h3>
									{tier.highlight ? (
										<span className="rounded-full border border-accent/40 bg-accent/15 px-2 py-0.5 text-[10px] text-accent tracking-[0.08em] uppercase">
											Most popular
										</span>
									) : null}
								</div>
								<p className="mt-1 text-muted-foreground text-sm">
									{tier.tagline}
								</p>
							</div>

							<div>
								<p className="font-bold font-[Montserrat] text-4xl text-foreground tracking-tight">
									{tier.price}
								</p>
								<p className="mt-1 text-muted-foreground text-xs">
									{tier.priceDetail}
								</p>
							</div>

							{tier.cta.kind === "waitlist" ? (
								<Button
									className={cn(
										tier.highlight
											? "bg-foreground text-background hover:bg-foreground/90"
											: "",
									)}
									variant={tier.highlight ? "default" : "outline"}
									onClick={() =>
										waitlist.open({
											source: "landing.pricing",
											tier:
												tier.cta.kind === "waitlist"
													? tier.cta.tier
													: undefined,
										})
									}
								>
									{tier.cta.label}
									<ArrowRight className="ml-2 h-3.5 w-3.5" />
								</Button>
							) : tier.cta.kind === "link" ? (
								<Button
									asChild
									className={cn(
										tier.highlight
											? "bg-foreground text-background hover:bg-foreground/90"
											: "",
									)}
									variant={tier.highlight ? "default" : "outline"}
								>
									<Link to={tier.cta.to}>
										{tier.cta.label}
										<ArrowRight className="ml-2 h-3.5 w-3.5" />
									</Link>
								</Button>
							) : (
								<Button
									asChild
									className={cn(
										tier.highlight
											? "bg-foreground text-background hover:bg-foreground/90"
											: "",
									)}
									variant={tier.highlight ? "default" : "outline"}
								>
									<a href={tier.cta.href}>
										{tier.cta.label}
										<ArrowRight className="ml-2 h-3.5 w-3.5" />
									</a>
								</Button>
							)}

							<ul className="flex flex-col gap-2.5 border-border/60 border-t pt-5">
								{tier.bullets.map((bullet) => (
									<li
										className="flex items-start gap-2 text-foreground text-sm leading-relaxed"
										key={bullet}
									>
										<Check className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
										<span>{bullet}</span>
									</li>
								))}
							</ul>
						</div>
					))}
				</div>

				<div className="mt-10 flex flex-col items-center gap-3 text-center">
					<p className="text-muted-foreground text-sm">
						Same Production Stacks across every tier. You pay for SLA, support,
						and team features — not for access to the recipes.
					</p>
					<Button
						asChild
						className="text-muted-foreground hover:text-foreground"
						variant="ghost"
					>
						<Link to="/pricing">
							Compare every feature
							<ArrowRight className="ml-2 h-3.5 w-3.5" />
						</Link>
					</Button>
				</div>
			</div>
		</section>
	);
}
