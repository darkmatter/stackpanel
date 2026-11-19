import * as Provider from "alchemy/Provider";
import { Resource } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import { docker } from "./exec";

export interface Volume
  extends Resource<
    "Docker.Volume",
    { name: string },
    { volumeName: string }
  > {}

/**
 * A resource that represents a Docker volume.
 */
export const Volume = Resource<Volume>("Docker.Volume");

/**
 * A provider that creates a Docker volume.
 * @returns A provider that creates a Docker volume.
 */
export const VolumeProvider = () =>
  Provider.succeed(Volume, {
    stables: ["volumeName"],
    reconcile: Effect.fnUntraced(function* ({ news, output }) {
      if (output?.volumeName !== news.name) {
        if (output) yield* docker("volume", "rm", output.volumeName).pipe(Effect.ignore);
        yield* docker("volume", "create", news.name);
      }
      return { volumeName: news.name };
    }),
    delete: ({ output }) => docker("volume", "rm", output.volumeName).pipe(Effect.ignore),
  });
