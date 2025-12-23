import { createFileRoute } from "@tanstack/react-router";
import {
	CTASection,
	DevExperienceSection,
	FeaturesSection,
	Footer,
	Header,
	HeroSection,
	InfrastructureSection,
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
				<FeaturesSection />
				<InfrastructureSection />
				<DevExperienceSection />
				<TerminalSection />
				<CTASection />
			</main>
			<Footer />
		</div>
	);
}
