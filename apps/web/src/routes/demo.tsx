import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";
import { useAgentEndpoint } from "@/lib/agent-endpoint";

/**
 * `/demo` is a thin redirect into the real Studio in demo mode.
 *
 * The actual demo experience lives at `/studio`; this route exists so
 * marketing CTAs and external links can deep-link into the demo with a
 * predictable URL. It boots the MSW worker, swaps the agent endpoint to
 * the in-browser mock, then bounces the user to `/studio/dashboard`.
 */
export const Route = createFileRoute("/demo")({
	component: DemoRedirect,
	head: () => ({
		meta: [
			{ title: "Stackpanel Studio · Live demo" },
			{
				name: "description",
				content:
					"Click around the real Stackpanel Studio against an in-browser mocked agent. No install required.",
			},
		],
	}),
});

function DemoRedirect() {
	const { useDemo } = useAgentEndpoint();
	const navigate = useNavigate();

	useEffect(() => {
		let cancelled = false;
		void (async () => {
			await useDemo();
			if (cancelled) return;
			void navigate({
				to: "/studio/dashboard",
				replace: true,
			});
		})();
		return () => {
			cancelled = true;
		};
	}, [useDemo, navigate]);

	return (
		<div className="flex h-svh items-center justify-center text-muted-foreground">
			Booting demo agent…
		</div>
	);
}
