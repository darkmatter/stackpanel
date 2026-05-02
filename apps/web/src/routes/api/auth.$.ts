import { createFileRoute } from "@tanstack/react-router";

const handleAuthRequest = async (request: Request) => {
	const { auth } = await import("@stackpanel/auth");
	return auth.handler(request);
};

export const Route = createFileRoute("/api/auth/$")({
	server: {
		handlers: {
			GET: ({ request }) => handleAuthRequest(request),
			POST: ({ request }) => handleAuthRequest(request),
		},
	},
});
