import * as Cloudflare from "alchemy/Cloudflare";
import * as D1 from "alchemy/Cloudflare/D1";
import * as Effect from "effect/Effect";
import { HttpServerRequest } from "effect/unstable/http/HttpServerRequest";
import * as HttpServerResponse from "effect/unstable/http/HttpServerResponse";
import { betterAuth } from "better-auth";

export default class Worker extends Cloudflare.Worker<Worker>()(
  "Backend",
  {
    main: import.meta.url,
  },
  Effect.gen(function* () {
    const users = yield* Users;

    const db = yield* D1.Database("BetterAuthDB", {});
    const connect = yield* D1.QueryDatabase(db);

    const auth = yield* Effect.gen(function* () {
      return betterAuth({
        database: yield* connect.raw,
        secret: "FOO",
      });
    }).pipe(Effect.cached);

    return {
      getProfile: (name: string) => users.getByName(name).getProfile(),
      putProfile: (name: string, value: string) => users.getByName(name).putProfile(value),
      fetch: Effect.gen(function* () {
        const request = yield* HttpServerRequest;
        const url = new URL(request.url);

        if (url.pathname.startsWith("/api/auth")) {
          const authInstance = yield* auth;
          const response = yield* Effect.promise(() =>
            authInstance.handler(request.source as Request),
          );
          return HttpServerResponse.fromWeb(response);
        }

        return HttpServerResponse.text("Hello World");
      }),
    };
  }).pipe(Effect.provide(D1.QueryDatabaseBinding)),
) {}

export class Users extends Cloudflare.DurableObject<Users>()(
  "Users",
  Effect.gen(function* () {
    const state = yield* Cloudflare.DurableObjectState;

    return Effect.succeed({
      getProfile: () => state.storage.get<string>("Profile"),
      putProfile: (value: string) => state.storage.put("Profile", value),
    });
  }),
) {}
