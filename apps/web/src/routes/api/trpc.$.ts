import { createFileRoute } from "@tanstack/react-router";
import { fetchRequestHandler } from "@trpc/server/adapters/fetch";

const handler = async (req: Request) => {
	const [{ appRouter, createTRPCContext }, { auth }] = await Promise.all([
		import("@stackpanel/api"),
		import("@stackpanel/auth"),
	]);

	return fetchRequestHandler({
		endpoint: "/api/trpc",
		router: appRouter,
		req,
		createContext: () =>
			createTRPCContext({
				auth: auth,
				headers: req.headers,
			}),
		onError({ error, path }) {
			console.error(`>>> tRPC Error on '${path}'`, error);
		},
	});
};

export const Route = createFileRoute("/api/trpc/$")({
	server: {
		handlers: {
			GET: ({ request }) => handler(request),
			POST: ({ request }) => handler(request),
		},
	},
});
