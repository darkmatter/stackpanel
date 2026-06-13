import { createFileRoute } from "@tanstack/react-router";
import {
	ComparisonSection,
	ConfigShowcaseSection,
	CTASection,
	DevExperienceSection,
	FeaturesSection,
	Footer,
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
		<div className="bg-background">
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
