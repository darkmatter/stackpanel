import * as Effect from "effect/Effect";
import * as Stream from "effect/Stream";
import { ChildProcess } from "effect/unstable/process";


/**
 * Run a command and return the stdout, stderr, and exit code.
 * @param command - The command to run.
 * @returns The stdout, stderr, and exit code of the command.
 */
export const exec = Effect.fn("exec")(function* (command: ChildProcess.Command) {
  const handle = yield* command;
  const [exitCode, stdout, stderr] = yield* Effect.all(
    [
      handle.exitCode,
      Stream.mkString(Stream.decodeText(handle.stdout)),
      Stream.mkString(Stream.decodeText(handle.stderr)),
    ],
    { concurrency: 3 },
  );
  return { exitCode, stdout, stderr };
});

/**
 * Run a docker command and return the stdout.
 * @param args - The arguments to pass to the docker command.
 * @returns The stdout of the docker command (trimmed).
 */
export const docker = (...args: string[]) =>
  exec(ChildProcess.make("docker", args)).pipe(
    Effect.map(({ stdout }) => stdout.trim()),
  );
