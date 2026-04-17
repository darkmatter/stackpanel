import * as Cloudflare from "alchemy-effect/Cloudflare"
import * as Effect from "effect/Effect"
import * as HttpServerResponse from "effect/unstable/http/HttpServerResponse"

export default class Worker extends Cloudflare.TanstackStart<Worker>()(
  "Backend",
   {
    main: import.meta.filename,
   },
   Effect.gen(function* () {
    const users = yield* Users

    return {
      getProfile: (name: string) => users.getByName(name).getProfile(),
      putProfile: (name: string, value: string) => users.getByName(name).putProfile(value),
      // oxlint-disable-next-line require-yield
      fetch: Effect.gen(function* () {
        return HttpServerResponse.text("Hello World");
      }),
    }
   }),
){}



export class Users extends Cloudflare.DurableObjectNamespace<Users>()(
  "Users",
  // oxlint-disable-next-line require-yield
  Effect.gen(function* () {
    // Namespace
    // e.g. add resources & bindings here:
    // const queue = yield* Cloudflare.Queue("UsersQueue");

    return Effect.gen(function* () {
      // Instance
      const state = yield* Cloudflare.DurableObjectState;
      return {
        getProfile: () => state.storage.get<string>("Profile"),
        putProfile: (value: string) => state.storage.put("Profile", value),
      };
    });
  }),
) {}