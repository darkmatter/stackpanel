import { createFileRoute, redirect, Link } from "@tanstack/react-router";

import { Button } from "@ui/button";
import { getUser } from "@/functions/get-user";

export const Route = createFileRoute("/dashboard")({
	component: RouteComponent,
	beforeLoad: async () => {
		const session = await getUser();
		return { session };
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
	const { session } = Route.useRouteContext();

	return (
		<div className="flex min-h-screen flex-col items-center justify-center gap-4">
			<h1 className="text-2xl font-bold">Dashboard</h1>
			<p>Welcome, {session?.user.name ?? "User"}!</p>
			<div className="flex gap-4">
				<Button asChild>
					<Link to="/studio">Go to Studio</Link>
				</Button>
			</div>
		</div>
	);
}
