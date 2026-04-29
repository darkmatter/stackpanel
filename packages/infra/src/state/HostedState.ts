import type { AppRouter } from "@stackpanel/api";
import {
	State,
	StateStoreError,
	type StateService,
} from "alchemy-effect/State";
import {
	createTRPCClient,
	httpBatchLink,
	TRPCClientError,
} from "@trpc/client";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import superjson from "superjson";

/**
 * Hosted alchemy state backend (Pro tier).
 *
 * Swaps alchemy-effect's filesystem `LocalState` Layer for one backed by
 * api.stackpanel.com. Every operation becomes an authenticated tRPC call;
 * the cloud refuses callers without an active Pro subscription.
 *
 * Usage in an alchemy.run.ts:
 *
 *   import { HostedState } from "@stackpanel/infra/state/HostedState";
 *
 *   export default Stack.make("WebStack", providers)(program).pipe(
 *     Effect.provide(HostedState),
 *   );
 *
 * Config is read from env so CI and local runs can flip backends with
 * the same binary:
 *   STACKPANEL_STATE_BACKEND=hosted      # opt in
 *   STACKPANEL_API_URL=...               # default https://api.stackpanel.com
 *   ALCHEMY_STATE_TOKEN=...              # capability JWT (Better-Auth session)
 *
 * Errors surface as StateStoreError so alchemy's CLI can print them
 * without leaking tRPC internals. 402/FORBIDDEN → a clear "Pro required"
 * message; everything else keeps the original tRPC shape text.
 */

type HostedStateClient = ReturnType<typeof createTRPCClient<AppRouter>>;

function resolveBaseUrl(): string {
	return (
		process.env.STACKPANEL_API_URL ??
		process.env.ALCHEMY_STATE_URL ??
		"https://api.stackpanel.com"
	);
}

function resolveToken(): string | undefined {
	return process.env.ALCHEMY_STATE_TOKEN ?? process.env.STACKPANEL_API_TOKEN;
}

function makeClient(): HostedStateClient {
	const url = `${resolveBaseUrl().replace(/\/$/, "")}/trpc`;
	const token = resolveToken();
	return createTRPCClient<AppRouter>({
		links: [
			httpBatchLink({
				url,
				transformer: superjson,
				headers: () => {
					const headers: Record<string, string> = {};
					if (token) headers.authorization = `Bearer ${token}`;
					return headers;
				},
			}),
		],
	});
}

function toStateStoreError(err: unknown): StateStoreError {
	if (err instanceof TRPCClientError) {
		const code = err.data?.code;
		if (code === "FORBIDDEN") {
			return new StateStoreError({
				message:
					"Hosted alchemy state requires an active Pro subscription. " +
					"Visit https://stackpanel.com/pricing or run `stackpanel subscription upgrade`.",
			});
		}
		if (code === "UNAUTHORIZED") {
			return new StateStoreError({
				message:
					"ALCHEMY_STATE_TOKEN is missing or invalid. " +
					"Run `stackpanel auth login` to refresh it.",
			});
		}
		if (code === "PRECONDITION_FAILED") {
			return new StateStoreError({
				message:
					"No active organization on your session. Run " +
					"`stackpanel org switch <slug>` or create one in the studio.",
			});
		}
		return new StateStoreError({
			message: `Hosted state ${code ?? "error"}: ${err.message}`,
			cause: err,
		});
	}
	const message = err instanceof Error ? err.message : String(err);
	return new StateStoreError({
		message,
		cause: err instanceof Error ? err : undefined,
	});
}

function liftPromise<A>(thunk: () => Promise<A>) {
	return Effect.tryPromise({
		try: thunk,
		catch: (err) => toStateStoreError(err),
	});
}

/**
 * StateService implementation. Most methods are a direct translation of
 * a tRPC procedure. `getReplacedResources` is the exception — the cloud
 * router doesn't filter by status (keeping it generic), so we compose
 * list + get here exactly like alchemy-effect's LocalState does.
 */
function buildService(client: HostedStateClient): StateService {
	const service: StateService = {
		listStacks: () =>
			liftPromise(() => client.alchemyState.listStacks.query()),

		listStages: (stack) =>
			liftPromise(() => client.alchemyState.listStages.query({ stack })),

		get: (request) =>
			liftPromise(() =>
				client.alchemyState.get.query(request).then((row) =>
					row ? (row.payload as never) : undefined,
				),
			),

		set: (request) =>
			liftPromise(() =>
				client.alchemyState.put
					.mutate({
						stack: request.stack,
						stage: request.stage,
						fqn: request.fqn,
						payload: request.value,
					})
					.then(() => request.value),
			),

		delete: (request) =>
			liftPromise(() =>
				client.alchemyState.delete.mutate(request).then(() => undefined),
			),

		list: (request) =>
			liftPromise(() =>
				client.alchemyState.list.query(request).then((rows) => rows.map((r) => r.fqn)),
			),

		getReplacedResources: Effect.fnUntraced(function* (request) {
			const fqns = yield* service.list(request);
			const states = yield* Effect.all(
				fqns.map((fqn) =>
					service.get({ stack: request.stack, stage: request.stage, fqn }),
				),
			);
			return states.filter(
				(s): s is NonNullable<typeof s> & { status: "replaced" } =>
					Boolean(s && s.status === "replaced"),
			);
		}),
	};
	return service;
}

/**
 * Layer you provide to swap in the hosted backend. Cached so repeated
 * yields share one tRPC client (one connection pool per process).
 */
export const HostedState = Layer.effect(
	State,
	Effect.gen(function* () {
		const client = yield* Effect.sync(makeClient);
		return buildService(client);
	}),
);
