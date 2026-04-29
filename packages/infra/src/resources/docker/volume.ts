import * as Provider from "alchemy/Provider";
import { Resource } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import { docker } from "@/lib/exec";

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
  Provider.effect(
    Volume,
    Effect.succeed(
      Volume.Provider.of({
        stables: ["volumeName"],
        create: Effect.fnUntraced(function* ({ news }) {
          yield* docker("volume", "create", news.name);
          return { volumeName: news.name };
        }),
        update: Effect.fnUntraced(function* ({ news, output }) {
          if (news.name !== output.volumeName) {
            yield* docker("volume", "rm", output.volumeName).pipe(
              Effect.ignore,
            );
            yield* docker("volume", "create", news.name);
          }
          return { volumeName: news.name };
        }),
        delete: Effect.fnUntraced(function* ({ output }) {
          yield* docker("volume", "rm", output.volumeName).pipe(
            Effect.ignore,
          );
        }),
      }),
    ),
  );
