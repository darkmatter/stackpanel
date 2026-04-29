import * as Neon from "@distilled.cloud/neon";
import {
  createProject,
  deleteProject,
  getConnectionURI,
  getProject,
} from "@distilled.cloud/neon/Operations";
import * as Provider from "alchemy/Provider";
import { Resource } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";

export interface NeonProjectProps {
  name: string;
  regionId?: string;
  pgVersion?: number;
  databaseName?: string;
  roleName?: string;
}

export interface NeonProject
  extends Resource<
    "Neon.Project",
    NeonProjectProps,
    {
      projectId: string;
      connectionUri: string;
      host: string;
      databaseName: string;
      roleName: string;
      regionId: string;
    }
  > {}

export const NeonProject = Resource<NeonProject>("Neon.Project");

export const NeonProjectProvider = () =>
  Provider.effect(
    NeonProject,
    Effect.succeed(
      NeonProject.Provider.of({
        stables: ["projectId"],

        read: Effect.fnUntraced(function* ({ output }) {
          if (!output?.projectId) return undefined;
          const result = yield* getProject({
            project_id: output.projectId,
          }).pipe(
            Effect.map(() => output),
            Effect.catchCause(() => Effect.succeed(undefined)),
          );
          return result;
        }),

        create: Effect.fnUntraced(function* ({ news }) {
          const dbName = news.databaseName ?? "neondb";
          const roleName = news.roleName ?? "neondb_owner";

          const result = yield* createProject({
            project: {
              name: news.name,
              region_id: news.regionId,
              pg_version: news.pgVersion,
              branch: {
                database_name: dbName,
                role_name: roleName,
              },
            },
          });

          const projectId = result.project.id;
          const uri = result.connection_uris[0];

          const connectionUri = uri
            ? Redacted.value(uri.connection_uri)
            : (yield* getConnectionURI({
                project_id: projectId,
                database_name: dbName,
                role_name: roleName,
              })).uri;

          return {
            projectId,
            connectionUri,
            host: uri?.connection_parameters.host ?? result.project.proxy_host,
            databaseName: dbName,
            roleName,
            regionId: result.project.region_id,
          };
        }),

        update: Effect.fnUntraced(function* ({ news, output }) {
          const dbName = news.databaseName ?? "neondb";
          const roleName = news.roleName ?? "neondb_owner";

          const { uri } = yield* getConnectionURI({
            project_id: output.projectId,
            database_name: dbName,
            role_name: roleName,
          });

          return {
            ...output,
            connectionUri: uri,
            databaseName: dbName,
            roleName,
          };
        }),

        delete: Effect.fnUntraced(function* ({ output }) {
          yield* deleteProject({ project_id: output.projectId }).pipe(
            Effect.ignore,
          );
        }),
      }),
    ),
  );

const neonCredentialsLayer = Layer.effect(
  Neon.Credentials as any,
  Effect.sync(() => ({
    apiKey: Redacted.make(process.env.NEON_API_KEY ?? "unused"),
    apiBaseUrl: Neon.DEFAULT_API_BASE_URL,
  })),
) as Layer.Layer<typeof Neon.Credentials>;

export const neonProviders = () =>
  NeonProjectProvider().pipe(Layer.provide(neonCredentialsLayer));
