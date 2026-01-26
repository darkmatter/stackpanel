import type { AppRouter } from "@stackpanel/api/routers/index";
import { QueryClient } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";
import { setupRouterSsrQueryIntegration } from "@tanstack/react-router-ssr-query";
import type { TRPCClient } from "@trpc/client";
import { createTRPCOptionsProxy } from "@trpc/tanstack-react-query";
import SuperJSON from "superjson";

import { makeTRPCClient, TRPCProvider } from "@/utils/trpc";
import { routeTree } from "./routeTree.gen";

export function getRouter() {
	const queryClient = new QueryClient({
		defaultOptions: {
			dehydrate: { serializeData: SuperJSON.serialize },
			hydrate: { deserializeData: SuperJSON.deserialize },
		},
	});
	// Note: makeTRPCClient uses createIsomorphicFn which has different return types
	// on server (async) vs client (sync). At runtime the build transform handles this,
	// but TypeScript sees the union. Cast is safe because the transform ensures
	// we get the right type in each environment.
	const trpcClient = makeTRPCClient() as TRPCClient<AppRouter>;
	const trpc = createTRPCOptionsProxy({
		client: trpcClient,
		queryClient,
	});

	const router = createRouter({
		routeTree,
		context: { queryClient, trpc },
		defaultPreload: "intent",
		Wrap: (props) => (
			<TRPCProvider
				trpcClient={trpcClient as TRPCClient<AppRouter>}
				queryClient={queryClient}
				{...props}
			/>
		),
	});
	setupRouterSsrQueryIntegration({
		router,
		queryClient,
	});

	return router;
}
