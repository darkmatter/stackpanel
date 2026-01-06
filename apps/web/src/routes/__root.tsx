/// <reference types="vite/client" />

import type { AppRouter } from "@stackpanel/api/routers/index";
import type { QueryClient } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import {
  createRootRouteWithContext,
  HeadContent,
  Outlet,
  Scripts,
  useRouterState,
} from "@tanstack/react-router";
import { TanStackRouterDevtools } from "@tanstack/react-router-devtools";
import type { TRPCOptionsProxy } from "@trpc/tanstack-react-query";
import Header from "@/components/header";
import { ThemeProvider } from "@/components/theme-provider";
import { Toaster } from "@/components/ui/sonner";
import "@fontsource-variable/montserrat";
import appCss from "@/styles.css?url";

export interface RouterAppContext {
  trpc: TRPCOptionsProxy<AppRouter>;
  queryClient: QueryClient;
}

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
    ],
    links: [
      {
        rel: "icon",
        href: "/favicon.ico",
      },
      {
        rel: "stylesheet",
        href: appCss,
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

function RootDocument({ children }: { children: React.ReactNode }) {
  const routerState = useRouterState();
  const pathname = routerState.location.pathname;
  const isFullScreenPage = [/^\/$/, /^\/(demo|studio)\/?/].some((regex) =>
    regex.test(pathname),
  );

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
        <body>
          {!isFullScreenPage && <Header />}
          <div className="grid h-svh grid-rows-[auto_1fr]">{children}</div>
          <Toaster richColors />
          <TanStackRouterDevtools position="bottom-left" />
          <ReactQueryDevtools buttonPosition="bottom-right" position="bottom" />
        </body>
      </html>
    </ThemeProvider>
  );
}
