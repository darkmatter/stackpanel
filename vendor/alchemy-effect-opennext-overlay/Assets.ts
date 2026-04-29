import * as workers from "@distilled.cloud/cloudflare/workers";
import * as Context from "effect/Context";
import * as Data from "effect/Data";
import * as Effect from "effect/Effect";
import * as FileSystem from "effect/FileSystem";
import * as Layer from "effect/Layer";
import * as Path from "effect/Path";
import type { PlatformError } from "effect/PlatformError";
import type { ScopedPlanStatusSession } from "../../Cli/Cli.ts";
import { sha256, sha256Object } from "../../Util/index.ts";

const MAX_ASSET_SIZE = 1024 * 1024 * 25; // 25MB
const MAX_ASSET_COUNT = 20_000;

export interface AssetsConfig extends Exclude<
  Exclude<workers.PutScriptRequest["metadata"]["assets"], undefined>["config"],
  undefined
> {}

/** Additional filesystem trees merged into the Worker asset manifest under a URL prefix. */
export interface AssetSource {
  readonly directory: string;
  /**
   * URL prefix for files from `directory` (no leading slash), e.g.
   * `cdn-cgi/_next_cache` for OpenNext static incremental cache.
   */
  readonly prefix: string;
}

export interface AssetReadResult {
  directory: string;
  config: AssetsConfig | undefined;
  manifest: Record<string, { hash: string; size: number }>;
  _headers: string | undefined;
  _redirects: string | undefined;
  hash: string;
  /**
   * Maps each manifest path to the absolute file to read at upload time
   * (base directory and overlays may differ).
   */
  filePaths: Record<string, string>;
}

export interface AssetsProps {
  directory: string;
  config?: AssetsConfig;
  /** Optional extra directories merged into the asset manifest (e.g. OpenNext `.open-next/cache`). */
  sources?: readonly AssetSource[];
}

export class Assets extends Context.Service<
  Assets,
  {
    read(
      directory: AssetsProps,
    ): Effect.Effect<AssetReadResult, PlatformError | ValidationError>;
    upload(
      accountId: string,
      workerName: string,
      assets: AssetReadResult,
      session: ScopedPlanStatusSession,
    ): Effect.Effect<
      { jwt: string | undefined },
      | PlatformError
      | ValidationError
      | workers.CreateScriptAssetUploadError
      | workers.CreateAssetUploadError
    >;
  }
>()("Cloudflare.Assets") {}

export type ValidationError =
  | AssetTooLargeError
  | TooManyAssetsError
  | AssetNotFoundError
  | FailedToReadAssetError
  | AssetPathCollisionError;

export class AssetTooLargeError extends Data.TaggedError("AssetTooLargeError")<{
  message: string;
  name: string;
  size: number;
}> {}

export class TooManyAssetsError extends Data.TaggedError("TooManyAssetsError")<{
  message: string;
  directory: string;
  count: number;
}> {}

export class AssetNotFoundError extends Data.TaggedError("AssetNotFoundError")<{
  message: string;
  hash: string;
}> {}

export class FailedToReadAssetError extends Data.TaggedError(
  "FailedToReadAssetError",
)<{
  message: string;
  name: string;
  cause: PlatformError;
}> {}

export class AssetPathCollisionError extends Data.TaggedError(
  "AssetPathCollisionError",
)<{
  message: string;
  publicPath: string;
}> {}

const normalizeUrlPrefix = (prefix: string) =>
  prefix.replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");

/** Build `/public/path` key for a file relative to an asset root and optional URL prefix. */
export const manifestPublicPath = (rootRelative: string, urlPrefix: string) => {
  const rel = (
    rootRelative.startsWith("/") ? rootRelative.slice(1) : rootRelative
  ).replace(/\\/g, "/");
  const p = normalizeUrlPrefix(urlPrefix);
  if (!p) {
    return `/${rel}`.replace(/\/+/g, "/");
  }
  return `/${p}/${rel}`.replace(/\/+/g, "/");
};

const getContentType = (name: string) => {
  if (name.endsWith(".html")) return "text/html";
  if (name.endsWith(".txt")) return "text/plain";
  if (name.endsWith(".sql")) return "text/sql";
  if (name.endsWith(".json")) return "application/json";
  if (name.endsWith(".js") || name.endsWith(".mjs")) {
    // Browsers only accept JavaScript module scripts when the MIME type is a
    // "JavaScript MIME type" (e.g. text/javascript). application/javascript+module
    // is not valid and causes strict module loading to fail.
    return "text/javascript; charset=utf-8";
  }
  if (name.endsWith(".css")) return "text/css";
  if (name.endsWith(".wasm")) return "application/wasm";
  if (name.endsWith(".png")) return "image/png";
  if (name.endsWith(".svg")) return "image/svg+xml";
  if (name.endsWith(".ico")) return "image/x-icon";
  return "application/octet-stream";
};

export const AssetsProvider = () =>
  Layer.effect(
    Assets,
    Effect.gen(function* () {
      const fs = yield* FileSystem.FileSystem;
      const path = yield* Path.Path;
      const createAssetUpload = yield* workers.createAssetUpload;
      const createScriptAssetUpload = yield* workers.createScriptAssetUpload;

      const maybeReadString = Effect.fnUntraced(function* (file: string) {
        return yield* fs.readFileString(file).pipe(
          Effect.catchIf(
            (error) =>
              error._tag === "PlatformError" &&
              error.reason._tag === "NotFound",
            () => Effect.succeed(undefined),
          ),
        );
      });

      const createIgnoreMatcher = Effect.fnUntraced(function* (
        patterns: string[],
      ) {
        const matcher = yield* Effect.promise(() =>
          import("ignore").then(({ default: ignore }) =>
            ignore().add(patterns),
          ),
        );
        return (file: string) => matcher.ignores(file);
      });

      return {
        read: Effect.fnUntraced(function* (props: AssetsProps) {
          const resolvedDirectory = path.resolve(props.directory);
          const [files, ignore, _headers, _redirects] = yield* Effect.all([
            fs.readDirectory(resolvedDirectory, { recursive: true }),
            maybeReadString(path.join(resolvedDirectory, ".assetsignore")),
            maybeReadString(path.join(resolvedDirectory, "_headers")),
            maybeReadString(path.join(resolvedDirectory, "_redirects")),
          ]);
          const ignores = yield* createIgnoreMatcher([
            ".assetsignore",
            "_headers",
            "_redirects",
            ...(ignore
              ?.split("\n")
              .map((line) => line.trim())
              .filter((line) => line.length > 0 && !line.startsWith("#")) ??
              []),
          ]);
          const manifest = new Map<string, { hash: string; size: number }>();
          const filePaths = new Map<string, string>();
          let count = 0;

          const addFile = Effect.fnUntraced(function* (
            rootRelative: string,
            absoluteFile: string,
            urlPrefix: string,
            countLabel: string,
          ) {
            const stat = yield* fs.stat(absoluteFile);
            if (stat.type !== "File") {
              return;
            }
            const size = Number(stat.size);
            if (size > MAX_ASSET_SIZE) {
              return yield* new AssetTooLargeError({
                message: `Asset ${rootRelative} is too large (the maximum size is ${MAX_ASSET_SIZE / 1024 / 1024} MB; this asset is ${size / 1024 / 1024} MB)`,
                name: rootRelative,
                size,
              });
            }
            const hash = yield* fs.readFile(absoluteFile).pipe(
              Effect.flatMap(sha256),
              Effect.map((h) => h.slice(0, 32)),
            );
            const key = manifestPublicPath(rootRelative, urlPrefix);
            const existing = manifest.get(key);
            if (existing) {
              if (existing.hash !== hash) {
                return yield* new AssetPathCollisionError({
                  message: `Conflicting asset content for public path ${key}`,
                  publicPath: key,
                });
              }
              return;
            }
            count++;
            if (count > MAX_ASSET_COUNT) {
              return yield* new TooManyAssetsError({
                message: `Too many assets (the maximum count is ${MAX_ASSET_COUNT}; this directory has ${count} assets)`,
                directory: countLabel,
                count,
              });
            }
            manifest.set(key, { hash, size });
            filePaths.set(key, absoluteFile);
          });

          yield* Effect.forEach(
            files,
            Effect.fnUntraced(function* (name) {
              if (ignores(name)) {
                return;
              }
              const absoluteFile = path.join(resolvedDirectory, name);
              yield* addFile(
                name,
                absoluteFile,
                "",
                props.directory,
              );
            }),
          );

          for (const source of props.sources ?? []) {
            const resolvedSource = path.resolve(source.directory);
            const overlayFiles = yield* fs.readDirectory(resolvedSource, {
              recursive: true,
            });
            const overlayIgnore = yield* maybeReadString(
              path.join(resolvedSource, ".assetsignore"),
            );
            const overlayIgnores = yield* createIgnoreMatcher([
              ".assetsignore",
              ...(overlayIgnore
                ?.split("\n")
                .map((line) => line.trim())
                .filter((line) => line.length > 0 && !line.startsWith("#")) ??
                []),
            ]);
            yield* Effect.forEach(
              overlayFiles,
              Effect.fnUntraced(function* (name) {
                if (overlayIgnores(name)) {
                  return;
                }
                const absoluteFile = path.join(resolvedSource, name);
                yield* addFile(
                  name,
                  absoluteFile,
                  source.prefix,
                  source.directory,
                );
              }),
            );
          }

          const sortedManifest = Object.fromEntries(
            Array.from(manifest.entries()).sort((a, b) =>
              a[0].localeCompare(b[0]),
            ),
          );
          const sortedFilePaths = Object.fromEntries(
            Array.from(filePaths.entries()).sort((a, b) =>
              a[0].localeCompare(b[0]),
            ),
          );
          const hashPayload = {
            directory: props.directory,
            config: props.config,
            manifest: sortedManifest,
            _headers,
            _redirects,
          };
          return {
            ...hashPayload,
            filePaths: sortedFilePaths,
            hash: yield* sha256Object(hashPayload),
          };
        }),
        upload: Effect.fnUntraced(function* (
          accountId: string,
          workerName: string,
          assets: AssetReadResult,
          { note }: ScopedPlanStatusSession,
        ) {
          yield* note("Checking assets...");
          const session = yield* createScriptAssetUpload({
            accountId,
            scriptName: workerName,
            manifest: assets.manifest,
          });
          if (!session.buckets?.length) {
            return { jwt: session.jwt ?? undefined };
          }
          if (!session.jwt) {
            return { jwt: undefined };
          }
          const uploadJwt = session.jwt;
          let uploaded = 0;
          const total = session.buckets.flat().length;
          yield* note(`Uploaded ${uploaded} of ${total} assets...`);
          const assetsByHash = new Map<string, string>();
          for (const [name, { hash }] of Object.entries(assets.manifest)) {
            assetsByHash.set(hash, name);
          }
          let jwt: string | undefined | null;
          const directory = path.resolve(assets.directory);
          yield* Effect.forEach(
            session.buckets,
            Effect.fnUntraced(function* (bucket) {
              const body: Record<string, File> = {};
              yield* Effect.forEach(
                bucket,
                Effect.fnUntraced(function* (hash) {
                  const name = assetsByHash.get(hash);
                  if (!name) {
                    return yield* new AssetNotFoundError({
                      message: `Asset ${hash} not found in manifest`,
                      hash,
                    });
                  }
                  const resolvedFile =
                    assets.filePaths[name] ?? path.join(directory, name);
                  const file = yield* fs.readFile(resolvedFile).pipe(
                    Effect.mapError(
                      (error) =>
                        new FailedToReadAssetError({
                          message: `Failed to read asset ${name}: ${error.message}`,
                          name,
                          cause: error,
                        }),
                    ),
                  );
                  body[hash] = new File(
                    [Buffer.from(file).toString("base64")],
                    hash,
                    {
                      type: getContentType(name),
                    },
                  );
                }),
              );
              const result = yield* createAssetUpload({
                accountId,
                base64: true,
                body,
                jwtToken: uploadJwt,
              });

              uploaded += bucket.length;
              yield* note(`Uploaded ${uploaded} of ${total} assets...`);
              if (result.jwt) {
                jwt = result.jwt;
              }
            }),
          );
          return { jwt: jwt ?? undefined };
        }),
      };
    }),
  );
