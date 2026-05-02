/// <reference types="vite-plus/client" />

import type { AppRouter } from "@stackpanel/api/routers/index";
import type { QueryClient } from "@tanstack/react-query";
import {
	createRootRouteWithContext,
	HeadContent,
	Outlet,
	Scripts,
	useRouterState,
} from "@tanstack/react-router";
import type { TRPCOptionsProxy } from "@trpc/tanstack-react-query";
import { Toaster } from "@ui/sonner";
import { lazy, Suspense, type ReactNode } from "react";
import Header from "@/components/header";
import { WaitlistProvider } from "@/components/landing/waitlist-dialog";
import { ThemeProvider } from "@/components/theme-provider";
import { AgentEndpointProvider } from "@/lib/agent-endpoint";
import "@fontsource-variable/montserrat";
import "@fontsource-variable/source-code-pro";
import appCss from "@/styles.css?url";
// import baseCss from "@stackpanel/ui-core/styles/base.css?url";
import "@fontsource-variable/inter";
import webcss from "@stackpanel/ui-core/styles/web.css?url";

export interface RouterAppContext {
	trpc: TRPCOptionsProxy<AppRouter>;
	queryClient: QueryClient;
}

const TanStackRouterDevtools = import.meta.env.DEV
	? lazy(() =>
			import("@tanstack/react-router-devtools").then((mod) => ({
				default: mod.TanStackRouterDevtools,
			})),
		)
	: null;

const ReactQueryDevtools = import.meta.env.DEV
	? lazy(() =>
			import("@tanstack/react-query-devtools").then((mod) => ({
				default: mod.ReactQueryDevtools,
			})),
		)
	: null;

export const Route = createRootRouteWithContext<RouterAppContext>()({
	component: RootComponent,
	head: () => ({
		meta: [
			{
				title: "StackPanel",
			},
			{
				name: "description",
				content: "StackPanel - Modern infrastructure for modern teams",
			},
			{
				name: "viewport",
				content:
					"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no",
			},
		],
		links: [
			{
				rel: "icon",
				href: "/img/favicon/favicon.ico",
			},
			{
				rel: "stylesheet",
				href: appCss,
			},
			// {
			//   rel: "stylesheet",
			//   href: baseCss,
			// },
			{
				rel: "stylesheet",
				href: webcss,
			},
		],
	}),
});

function RootComponent() {
	return (
		<RootDocument>
			<Outlet />
		</RootDocument>
	);
}

function RootDocument({ children }: { children: ReactNode }) {
	const routerState = useRouterState();
	const pathname = routerState.location.pathname;
	const isFullScreenPage = [/^\/$/, /^\/(demo|studio)\/?/].some((regex) =>
		regex.test(pathname),
	);
	const isStudio = /^\/studio\/?/.test(pathname);

	return (
		<ThemeProvider
			attribute="class"
			defaultTheme="dark"
			disableTransitionOnChange
			storageKey="vite-ui-theme"
		>
			<html lang="en" suppressHydrationWarning>
				<head>
					<HeadContent />
					<Scripts />
				</head>
				<body className={isStudio ? "studio" : ""}>
					<AgentEndpointProvider>
						<WaitlistProvider>
							{!isFullScreenPage && <Header />}
							<div className="grid h-svh grid-rows-[auto_1fr]">{children}</div>
						</WaitlistProvider>
					</AgentEndpointProvider>
					<Toaster richColors />
					{TanStackRouterDevtools && ReactQueryDevtools && (
						<Suspense fallback={null}>
							<TanStackRouterDevtools position="bottom-left" />
							<ReactQueryDevtools
								buttonPosition="bottom-right"
								position="bottom"
							/>
						</Suspense>
					)}
				</body>
			</html>
		</ThemeProvider>
	);
}
