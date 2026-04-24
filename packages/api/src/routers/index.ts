import { createTRPCRouter } from "../trpc";
import { agentRouter } from "./agent";
import { alchemyStateRouter } from "./alchemy-state";
import { githubRouter } from "./github";

export const appRouter = createTRPCRouter({
  agent: agentRouter,
  alchemyState: alchemyStateRouter,
  github: githubRouter,
});

export type AppRouter = typeof appRouter;
