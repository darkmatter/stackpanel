import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/studio/")({
	component: RouteComponent,
});

function RouteComponent() {
	return <div>Hello "/studio/"!</div>;
}
