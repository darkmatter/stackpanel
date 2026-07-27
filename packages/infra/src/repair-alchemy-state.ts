import { loaders } from "@gen/env";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as State from "alchemy/State";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

interface RepairTarget {
  readonly stack: string;
  readonly stage: string;
  readonly fqn: string;
}

const targets = parseTargets(
  (process.env.REPAIR_ALCHEMY_STATE_TARGETS ?? "").split(/\s+/).filter(Boolean),
);

if (targets.length === 0) {
  console.error(
    "Set REPAIR_ALCHEMY_STATE_TARGETS='<stack>/<stage>/<fqn> ...' before running this repair stack.",
  );
  process.exit(1);
}

await loaders.deploy({ inject: true, validate: true });

const repairTarget = (target: RepairTarget) =>
  Effect.gen(function* () {
    // Alchemy's State tag yields an Effect<StateService> (ServiceClass
    // wraps the service in an Effect), so double-yield like alchemy's own
    // Apply.js does. Single-yield leaves an Effect object whose `.get` is
    // undefined at runtime.
    const state = yield* yield* State.State;
    const key = formatTarget(target);
    const value = yield* state.get(target).pipe(
      Effect.catch((error) =>
        Effect.gen(function* () {
          console.warn(
            `[alchemy-state-repair] deleting unreadable state record ${key}: ${formatError(error)}`,
          );
          yield* state.delete(target);
          console.log(`[alchemy-state-repair] deleted ${key}`);
          return undefined;
        }),
      ),
    );

    if (value === undefined) {
      console.log(`[alchemy-state-repair] ${key} is absent after repair`);
      return;
    }

    console.log(
      `[alchemy-state-repair] ${key} decoded successfully; keeping it`,
    );
  });

export default Alchemy.Stack(
  "StateRepair",
  {
    providers: Cloudflare.providers() as Layer.Layer<any, never, any>,
    state: Cloudflare.state() as Layer.Layer<any, never, any>,
  },
  Effect.forEach(targets, repairTarget, { concurrency: 1 }).pipe(Effect.orDie),
);

function parseTargets(args: ReadonlyArray<string>): RepairTarget[] {
  return args.map((arg) => {
    const [stack, stage, ...fqnParts] = arg.split("/");
    const fqn = fqnParts.join("/");
    if (!stack || !stage || !fqn) {
      throw new Error(`Invalid repair target: ${arg}`);
    }
    return { stack, stage, fqn };
  });
}

function formatTarget(target: RepairTarget): string {
  return `${target.stack}/${target.stage}/${target.fqn}`;
}

function formatError(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
