import { createTRPCRouter } from "../trpc";
import { agentRouter } from "./agent";
import { githubRouter } from "./github";

export const appRouter = createTRPCRouter({
  agent: agentRouter,
  github: githubRouter,
});

export type AppRouter = typeof appRouter;
