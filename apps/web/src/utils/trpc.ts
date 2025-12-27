import type { AppRouter } from "@stackpanel/api/routers/index";
import { createIsomorphicFn } from "@tanstack/react-start";
import {
	createTRPCClient,
	httpBatchStreamLink,
	loggerLink,
} from "@trpc/client";
import { createTRPCContext } from "@trpc/tanstack-react-query";
import SuperJSON from "superjson";

export const makeTRPCClient = createIsomorphicFn()
	.server(async () => {
		// Dynamic imports for server-only modules to avoid bundling @trpc/server on client
		const { appRouter, createTRPCContext: createServerContext } = await import(
			"@stackpanel/api"
		);
		const { auth } = await import("@stackpanel/auth");
		const { getRequestHeaders } = await import("@tanstack/react-start/server");
		const { unstable_localLink } = await import("@trpc/client");

		return createTRPCClient<AppRouter>({
			links: [
				unstable_localLink({
					router: appRouter,
					transformer: SuperJSON,
					createContext: () => {
						const headers = new Headers(getRequestHeaders());
						headers.set("x-trpc-source", "tanstack-start-server");
						return createServerContext({ auth, headers });
					},
				}),
			],
		});
	})
	.client(() => {
		const isDev = import.meta.env.DEV;
		return createTRPCClient<AppRouter>({
			links: [
				loggerLink({
					enabled: (op) =>
						isDev || (op.direction === "down" && op.result instanceof Error),
				}),
				httpBatchStreamLink({
					transformer: SuperJSON,
					url: "/api/trpc",
					headers() {
						const headers = new Headers();
						headers.set("x-trpc-source", "tanstack-start-client");
						return headers;
					},
				}),
			],
		});
	});

export const { useTRPC, TRPCProvider } = createTRPCContext<AppRouter>();
