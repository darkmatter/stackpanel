import * as Provider from "alchemy/Provider";
import { Resource } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { docker } from "./exec";
import { VolumeProvider } from "./docker.volume";

export interface ContainerProps {
  image: string;
  name: string;
  ports?: Array<{ external: number | string; internal: number | string }>;
  environment?: Record<string, string>;
  volumes?: Array<{ source: string; target: string }>;
  healthcheck?: {
    cmd: string[];
    interval?: string;
    timeout?: string;
    retries?: number;
    startPeriod?: string;
  };
  restart?: "no" | "always" | "on-failure" | "unless-stopped";
}

/**
 * A resource that represents a Docker container.
 */
export interface Container
  extends Resource<
    "Docker.Container",
    ContainerProps,
    { containerId: string; containerName: string }
  > {}

export const Container = Resource<Container>("Docker.Container");

/**
 * Build the arguments for the Docker run command.
 * @param props - The properties of the container.
 * @returns The arguments for the Docker run command.
 */
function buildRunArgs(props: ContainerProps): string[] {
  const args = ["run", "-d", "--name", props.name];

  if (props.restart) args.push("--restart", props.restart);

  for (const p of props.ports ?? []) {
    args.push("-p", `${p.external}:${p.internal}`);
  }
  for (const [k, v] of Object.entries(props.environment ?? {})) {
    args.push("-e", `${k}=${v}`);
  }
  for (const v of props.volumes ?? []) {
    args.push("-v", `${v.source}:${v.target}`);
  }
  if (props.healthcheck) {
    const hc = props.healthcheck;
    args.push("--health-cmd", hc.cmd.join(" "));
    if (hc.interval) args.push("--health-interval", hc.interval);
    if (hc.timeout) args.push("--health-timeout", hc.timeout);
    if (hc.retries) args.push("--health-retries", String(hc.retries));
    if (hc.startPeriod) args.push("--health-start-period", hc.startPeriod);
  }

  args.push(props.image);
  return args;
}

/**
 * A provider that creates a Docker container.
 * @returns A provider that creates a Docker container.
 */
export const ContainerProvider = () =>
  Provider.effect(
    Container,
    Effect.succeed(
      Container.Provider.of({
        stables: ["containerId"],
        create: Effect.fnUntraced(function* ({ news }) {
          yield* docker("rm", "-f", news.name).pipe(Effect.ignore);

          const id = yield* docker(...buildRunArgs(news));
          return { containerId: id, containerName: news.name };
        }),
        update: Effect.fnUntraced(function* ({ news, output }) {
          yield* docker("rm", "-f", output.containerName).pipe(Effect.ignore);
          const id = yield* docker(...buildRunArgs(news));
          return { containerId: id, containerName: news.name };
        }),
        delete: Effect.fnUntraced(function* ({ output }) {
          yield* docker("rm", "-f", output.containerName).pipe(Effect.ignore);
        }),
      }),
    ),
  );

// ---------------------------------------------------------------------------
// Combined providers Layer
// ---------------------------------------------------------------------------

export const providers = () =>
  Layer.mergeAll(VolumeProvider(), ContainerProvider());
