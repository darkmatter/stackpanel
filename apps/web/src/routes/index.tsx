import { createFileRoute } from "@tanstack/react-router";
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

export const Route = createFileRoute("/")({
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
