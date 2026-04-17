import { createFileRoute } from "@tanstack/react-router";
import { createServerFn } from "@tanstack/react-start";
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
import { useState } from "react";

export const getServerTime = createServerFn({
  method: "GET",
}).handler(() => ({
  message: "Hello from a TanStack Start server function.",
  time: new Date().toISOString(),
}));


export const Route = createFileRoute("/")({
	loader: () => getServerTime(),
	component: LandingPage,
});

function LandingPage() {
	const initialData = Route.useLoaderData();
	const [data, setData] = useState(initialData);
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

			<button
				type="button"
				onClick={async () => {
					setData(await getServerTime());
				}}
			>
				Refresh from server {JSON.stringify(data)}
			</button>
		</div>
	);
}
