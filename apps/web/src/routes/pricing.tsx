import { createFileRoute } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { ArrowRight, Check, Minus } from "lucide-react";
import { Fragment } from "react";
import { Footer, Header, PricingSection } from "@/components/landing";
import { useWaitlist } from "@/components/landing/waitlist-dialog";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/pricing")({
	component: PricingPage,
	head: () => ({
		meta: [
			{ title: "Pricing · Stackpanel" },
			{
				name: "description",
				content:
					"Stackpanel core is MIT and free forever. Subscribe to outsource the maintenance of your production deploys to a team that does it full-time.",
			},
		],
	}),
});

type Cell = "yes" | "no" | string;

type Row = {
	feature: string;
	detail?: string;
	community: Cell;
	team: Cell;
	business: Cell;
	enterprise: Cell;
};

type Section = {
	title: string;
	rows: Row[];
};

const sections: Section[] = [
	{
		title: "Stackpanel core",
		rows: [
			{
				feature: "Reproducible devshells",
				detail: "Nix · devenv · IDE config · scripts on PATH",
				community: "yes",
				team: "yes",
				business: "yes",
				enterprise: "yes",
			},
			{
				feature: "Encrypted secrets, deterministic ports, real HTTPS",
				community: "yes",
				team: "yes",
				business: "yes",
				enterprise: "yes",
			},
			{
				feature: "Type-safe @gen/env per app",
				community: "yes",
				team: "yes",
				business: "yes",
				enterprise: "yes",
			},
			{
				feature: "Studio (web + agent)",
				community: "yes",
				team: "yes",
				business: "yes",
				enterprise: "yes",
			},
		],
	},
	{
		title: "Production Stacks",
		rows: [
			{
				feature: "Alchemy · Colmena · Fly.io stacks",
				community: "Community branch",
				team: "Stable branch",
				business: "Stable + early access",
				enterprise: "Stable + early access + custom",
			},
			{
				feature: "Update cadence",
				community: "When merged",
				team: "Same-day stable",
				business: "Same-day + RC channel",
				enterprise: "Custom backports",
			},
			{
				feature: "Patch SLA",
				community: "Best-effort",
				team: "30 days",
				business: "7 days",
				enterprise: "24h critical CVE",
			},
			{
				feature: "Marketplace stacks",
				detail: "Coming soon — install third-party stacks via Studio",
				community: "Public only",
				team: "Public + paid",
				business: "Public + paid",
				enterprise: "Public + paid + private",
			},
		],
	},
	{
		title: "Team & access",
		rows: [
			{
				feature: "Seats",
				community: "1",
				team: "Unlimited",
				business: "Unlimited",
				enterprise: "Unlimited",
			},
			{
				feature: "Multi-org",
				community: "no",
				team: "no",
				business: "yes",
				enterprise: "yes",
			},
			{
				feature: "SSO (SAML / OIDC)",
				community: "no",
				team: "no",
				business: "yes",
				enterprise: "yes",
			},
			{
				feature: "SCIM provisioning",
				community: "no",
				team: "no",
				business: "no",
				enterprise: "yes",
			},
			{
				feature: "Audit log",
				community: "no",
				team: "no",
				business: "90 days",
				enterprise: "Unlimited + SIEM export",
			},
			{
				feature: "Custom RBAC",
				community: "no",
				team: "no",
				business: "no",
				enterprise: "yes",
			},
		],
	},
	{
		title: "Support",
		rows: [
			{
				feature: "Channel",
				community: "GitHub Discussions",
				team: "Email",
				business: "Discord + email",
				enterprise: "Slack + on-call + named CSM",
			},
			{
				feature: "Response time",
				community: "Community",
				team: "Next business day",
				business: "4 business hours",
				enterprise: "Custom (incl. 24/7)",
			},
			{
				feature: "Migration assistance",
				community: "no",
				team: "no",
				business: "Best-effort",
				enterprise: "yes",
			},
		],
	},
	{
		title: "Compliance & legal",
		rows: [
			{
				feature: "Air-gapped mirror license",
				detail: "Self-host the private flake mirror in your VPC",
				community: "no",
				team: "no",
				business: "no",
				enterprise: "yes",
			},
			{
				feature: "Indemnification",
				community: "no",
				team: "no",
				business: "no",
				enterprise: "yes",
			},
			{
				feature: "DPA / MSA / custom security review",
				community: "no",
				team: "no",
				business: "DPA available",
				enterprise: "Custom",
			},
		],
	},
];

const tierHeaders = [
	{ key: "community" as const, label: "Community" },
	{ key: "team" as const, label: "Team", emphasis: true },
	{ key: "business" as const, label: "Business" },
	{ key: "enterprise" as const, label: "Enterprise" },
];

function CellContent({ value }: { value: Cell }) {
	if (value === "yes") {
		return (
			<span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-accent/15 text-accent">
				<Check className="h-4 w-4" />
			</span>
		);
	}
	if (value === "no") {
		return (
			<span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-muted/30 text-muted-foreground/60">
				<Minus className="h-4 w-4" />
			</span>
		);
	}
	return <span className="text-foreground text-sm">{value}</span>;
}

const faqs: { q: string; a: string }[] = [
	{
		q: "Will the Stackpanel core ever stop being open source?",
		a: "No. The core (CLI, agent, Studio web app, every dev-environment feature) is MIT and stays MIT. Subscriptions only fund the maintenance of the production-deploy stacks.",
	},
	{
		q: "What does my subscription actually unlock?",
		a: "Access to the private stable branch of every Production Stack via a token-gated Nix flake input, plus the SLA, support channel, and team features in your tier. The recipes themselves are visible in our docs — you're paying for the commitment to keep them working.",
	},
	{
		q: "Can I use the community branch in production?",
		a: "Yes. The community branch is the same source as the stable branch, just on a slower release cadence with no patch SLA. Many teams ship to production on it. The trade-off is that when nixpkgs ships a breaking change you wait for the community to merge a fix instead of getting a same-day patch.",
	},
	{
		q: "Do I need a separate Stackpanel account per project?",
		a: "No. One subscription covers every project under your organization. Add as many flakes as you want — the per-user pricing scales with your team, not your projects.",
	},
	{
		q: "What happens if I cancel?",
		a: "Your apps keep running — they're deployed to your infrastructure, not ours. You lose access to future stable patches via the private input, but you can switch any flake input back to the public community branch with a one-line config change.",
	},
	{
		q: "Can I publish my own Production Stacks?",
		a: "The Marketplace is in private beta — Stackpanel takes 20%, you keep 80%. If you have a stack you'd like to publish, get in touch.",
	},
	{
		q: "Do you offer educational, non-profit, or open-source maintainer discounts?",
		a: "Yes — get in touch and we'll set you up. Approved OSS maintainers get Team for free.",
	},
];

function PricingPage() {
	return (
		<div className="min-h-screen bg-background">
			<Header />
			<main>
				<PricingSection />

				<section className="border-border border-b bg-secondary/10">
					<div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
						<div className="text-center">
							<p className="font-medium text-accent text-sm">
								Compare every feature
							</p>
							<h2 className="mt-3 font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
								Side-by-side
							</h2>
						</div>

						<div className="mt-10 overflow-hidden rounded-2xl border border-border bg-card">
							<div className="overflow-x-auto">
								<table className="w-full min-w-[920px] text-left">
									<thead className="border-border border-b bg-secondary/40">
										<tr>
											<th className="w-[28%] px-6 py-4 font-semibold text-foreground text-sm">
												&nbsp;
											</th>
											{tierHeaders.map((h) => (
												<th
													className={cn(
														"px-4 py-4 text-center font-semibold text-foreground text-sm",
														h.emphasis && "text-accent",
													)}
													key={h.key}
												>
													{h.label}
												</th>
											))}
										</tr>
									</thead>
									<tbody>
										{sections.map((section) => (
											<Fragment key={section.title}>
												<tr className="border-border border-y bg-secondary/20">
													<td
														className="px-6 py-3 font-medium text-foreground text-xs tracking-[0.06em] uppercase"
														colSpan={5}
													>
														{section.title}
													</td>
												</tr>
												{section.rows.map((row) => (
													<tr
														className="border-border/40 border-b last:border-b-0 transition-colors hover:bg-secondary/20"
														key={`${section.title}-${row.feature}`}
													>
														<td className="px-6 py-4">
															<p className="font-medium text-foreground text-sm">
																{row.feature}
															</p>
															{row.detail ? (
																<p className="mt-0.5 text-muted-foreground text-xs">
																	{row.detail}
																</p>
															) : null}
														</td>
														{tierHeaders.map((h) => (
															<td
																className={cn(
																	"px-4 py-4 text-center align-middle",
																	h.emphasis && "bg-accent/[0.04]",
																)}
																key={`${section.title}-${row.feature}-${h.key}`}
															>
																<div className="flex justify-center">
																	<CellContent value={row[h.key]} />
																</div>
															</td>
														))}
													</tr>
												))}
											</Fragment>
										))}
									</tbody>
								</table>
							</div>
						</div>
					</div>
				</section>

				<section className="border-border border-b">
					<div className="mx-auto max-w-3xl px-4 py-20 sm:px-6 lg:px-8">
						<div className="text-center">
							<p className="font-medium text-accent text-sm">FAQ</p>
							<h2 className="mt-3 font-bold font-[Montserrat] text-3xl text-foreground sm:text-4xl">
								Answers, in plain English
							</h2>
						</div>

						<div className="mt-10 divide-y divide-border/60 rounded-2xl border border-border bg-card">
							{faqs.map((faq) => (
								<div className="p-6" key={faq.q}>
									<h3 className="font-semibold text-foreground">{faq.q}</h3>
									<p className="mt-2 text-muted-foreground text-sm leading-relaxed">
										{faq.a}
									</p>
								</div>
							))}
						</div>

						<div className="mt-10 flex flex-col items-center gap-3 rounded-2xl border border-border bg-secondary/30 p-8 text-center">
							<p className="text-muted-foreground text-sm">
								Still have questions?
							</p>
							<div className="flex flex-wrap justify-center gap-3">
								<Button
									asChild
									className="bg-foreground text-background hover:bg-foreground/90"
								>
									<a href="mailto:hello@stackpanel.dev">
										Email us
										<ArrowRight className="ml-2 h-4 w-4" />
									</a>
								</Button>
								<JoinWaitlistButton variant="outline" source="pricing.faq">
									Join the waitlist
								</JoinWaitlistButton>
							</div>
						</div>
					</div>
				</section>
			</main>
			<Footer />
		</div>
	);
}

function JoinWaitlistButton({
	children,
	source,
	variant = "default",
}: {
	children: React.ReactNode;
	source: string;
	variant?: "default" | "outline";
}) {
	const waitlist = useWaitlist();
	return (
		<Button variant={variant} onClick={() => waitlist.open({ source })}>
			{children}
		</Button>
	);
}
