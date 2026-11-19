import * as Cloudflare from "@alchemy.run/cloudflare";
import * as Effect from "effect/Effect";
import * as HttpServerResponse from "effect/http/HttpServerResponse";

export default class Worker extends Cloudflare.Worker<Worker>()(
  "Backend",
  {
    main: import.meta.url,
  },
  Effect.gen(function* () {
    const users = yield* Users;

    return {
      getProfile: (name: string) => users.getByName(name).getProfile(),
      putProfile: (name: string, value: string) => users.getByName(name).putProfile(value),
      fetch: Effect.succeed(HttpServerResponse.text("Hello World")),
    };
  }),
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
