import { createTRPCRouter } from "../trpc";
import { agentRouter } from "./agent";
import { alchemyStateRouter } from "./alchemy-state";
import { githubRouter } from "./github";
import { waitlistRouter } from "./waitlist";

export const appRouter = createTRPCRouter({
  agent: agentRouter,
  alchemyState: alchemyStateRouter,
  github: githubRouter,
  waitlist: waitlistRouter,
});

export type AppRouter = typeof appRouter;
