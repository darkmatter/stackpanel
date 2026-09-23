import { createTRPCRouter } from "../trpc";
import { agentRouter } from "./agent";
import { alchemyStateRouter } from "./alchemy-state";
import { waitlistRouter } from "./waitlist";

export const appRouter = createTRPCRouter({
  agent: agentRouter,
  alchemyState: alchemyStateRouter,
  waitlist: waitlistRouter,
});

export type AppRouter = typeof appRouter;
