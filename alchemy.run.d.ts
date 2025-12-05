import { Worker } from "alchemy/cloudflare";
export declare const web: Worker<
  {
    VITE_SERVER_URL: string;
  } & {
    ASSETS: import("alchemy/cloudflare").Assets;
  }
>;
export declare const server: Worker<
  {
    readonly DATABASE_URL: import("alchemy").Secret<string>;
    readonly CORS_ORIGIN: string;
    readonly BETTER_AUTH_SECRET: import("alchemy").Secret<string>;
    readonly BETTER_AUTH_URL: string;
    readonly GOOGLE_GENERATIVE_AI_API_KEY: import("alchemy").Secret<string>;
    readonly POLAR_ACCESS_TOKEN: import("alchemy").Secret<string>;
    readonly POLAR_SUCCESS_URL: string;
  },
  Rpc.WorkerEntrypointBranded
>;
