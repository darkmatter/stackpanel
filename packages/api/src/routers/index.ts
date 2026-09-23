import { createTRPCRouter } from "../trpc";
import { alchemyStateRouter } from "./alchemy-state";
import { waitlistRouter } from "./waitlist";

export const appRouter = createTRPCRouter({
  alchemyState: alchemyStateRouter,
  waitlist: waitlistRouter,
});

export type AppRouter = typeof appRouter;
