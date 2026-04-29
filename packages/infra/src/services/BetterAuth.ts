import * as Cloudflare from "alchemy/Cloudflare";
import * as D1 from "alchemy/Cloudflare/D1";
import type { HttpEffect } from "alchemy/Http";
import { betterAuth, type Auth } from "better-auth";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Context from "effect/Context";
import { HttpServerRequest } from "effect/unstable/http/HttpServerRequest";
import * as HttpServerResponse from "effect/unstable/http/HttpServerResponse";

export class BetterAuth extends Context.Service<
  BetterAuth,
  {
    auth: Effect.Effect<Auth<any>>;
    fetch: HttpEffect<Cloudflare.WorkerEnvironment | Cloudflare.WorkerServices>;
  }
>()("BetterAuth") {}

export const BetterAuthLive = Layer.effect(
  BetterAuth,
  Effect.gen(function* () {
    const db = yield* D1.Database("BetterAuthDB", {});

    const connect = yield* D1.D1Connection.bind(db);

    const auth = yield* Effect.gen(function* () {
      return betterAuth({
        database: yield* connect.raw,
        secret: "FOO",
      });
    }).pipe(Effect.cached);

    return {
      auth,
      fetch: Effect.gen(function* () {
        const request = yield* HttpServerRequest;
        const authInstance = yield* auth;
        const response = yield* Effect.promise(() =>
          authInstance.handler(request.source as Request),
        );
        return HttpServerResponse.fromWeb(response);
      }),
    };
  }),
).pipe(Layer.provide(D1.D1ConnectionLive));