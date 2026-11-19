import * as Cloudflare from "@alchemy.run/cloudflare";
import * as D1 from "@alchemy.run/cloudflare/D1";
import type { HttpEffect } from "alchemy/Http";
import type { RuntimeContext } from "alchemy";
import { betterAuth, type Auth } from "better-auth";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Context from "effect/Context";
import * as HttpServerResponse from "effect/http/HttpServerResponse";

export class BetterAuth extends Context.Service<
  BetterAuth,
  {
    auth: Effect.Effect<Auth<any>, never, RuntimeContext>;
    fetch: HttpEffect<Cloudflare.Request | RuntimeContext>;
  }
>()("BetterAuth") {}

export const BetterAuthLive = Layer.effect(
  BetterAuth,
  Effect.gen(function* () {
    const db = yield* D1.Database("BetterAuthDB", {});

    const connect = yield* D1.QueryDatabase(db);

    const auth = yield* Effect.gen(function* () {
      return betterAuth({
        database: yield* connect.raw,
        secret: "FOO",
      });
    }).pipe(Effect.cached);

    return {
      auth,
      fetch: Effect.gen(function* () {
        const request = yield* Cloudflare.Request;
        const authInstance = yield* auth;
        const response = yield* Effect.promise(() => authInstance.handler(request));
        return HttpServerResponse.fromWeb(response);
      }),
    };
  }),
).pipe(Layer.provide(D1.QueryDatabaseBinding));
