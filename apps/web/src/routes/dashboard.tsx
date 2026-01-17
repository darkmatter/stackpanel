import { useQuery } from "@tanstack/react-query";
import { createFileRoute, redirect } from "@tanstack/react-router";

import { Button } from "@ui/button";
import { getPayment } from "@/functions/get-payment";
import { getUser } from "@/functions/get-user";
import { authClient } from "@/lib/auth-client";
import { useTRPC } from "@/utils/trpc";

export const Route = createFileRoute("/dashboard")({
	component: RouteComponent,
	beforeLoad: async () => {
		const session = await getUser();
		const customerState = await getPayment();
		return { session, customerState };
	},
	loader: async ({ context }) => {
		if (!context.session) {
			throw redirect({
				to: "/login",
			});
		}
	},
});

function RouteComponent() {
	const { session, customerState } = Route.useRouteContext();

	const trpc = useTRPC();
	const privateData = useQuery(trpc.privateData.queryOptions());

	const hasProSubscription =
		(customerState?.activeSubscriptions?.length ?? 0) > 0;
	// For debugging: console.log("Active subscriptions:", customerState?.activeSubscriptions);

	return (
		<div>
			<h1>Dashboard</h1>
			<p>Welcome {session?.user.name}</p>
			<p>API: {privateData.data?.message}</p>
			<p>Plan: {hasProSubscription ? "Pro" : "Free"}</p>
			{hasProSubscription ? (
				<Button
					onClick={async function handlePortal() {
						await authClient.customer.portal();
					}}
				>
					Manage Subscription
				</Button>
			) : (
				<Button
					onClick={async function handleUpgrade() {
						await authClient.checkout({ slug: "pro" });
					}}
				>
					Upgrade to Pro
				</Button>
			)}
		</div>
	);
}
