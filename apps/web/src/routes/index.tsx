import { createFileRoute, redirect } from "@tanstack/react-router";
import {
	ComparisonSection,
	ConfigShowcaseSection,
	CTASection,
	DevExperienceSection,
	FeaturesSection,
	Footer,
	Header,
	HeroSection,
	HowItWorksSection,
	InfrastructureSection,
	PricingSection,
	ProductionStacksSection,
	StatsSection,
	TerminalSection,
} from "@/components/landing";
import { isStudioHost, resolveRequestHostname } from "@/lib/studio-host";

export const Route = createFileRoute("/")({
	beforeLoad: async () => {
		const hostname = await resolveRequestHostname();
		if (hostname && isStudioHost(hostname)) {
			throw redirect({ to: "/login" });
		}
	},
	component: LandingPage,
});

function LandingPage() {
	return (
		<div className="min-h-screen bg-background">
			<Header />
			<main>
				<HeroSection />
				<StatsSection />
				<HowItWorksSection />
				<FeaturesSection />
				<ConfigShowcaseSection />
				<InfrastructureSection />
				<ProductionStacksSection />
				<DevExperienceSection />
				<TerminalSection />
				<ComparisonSection />
				<PricingSection />
				<CTASection />
			</main>
			<Footer />
		</div>
	);
}
