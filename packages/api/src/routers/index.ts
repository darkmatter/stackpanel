import { createTRPCRouter } from "../trpc";
import { agentRouter } from "./agent";
import { todoRouter } from "./todo";

export const appRouter = createTRPCRouter({
  agent: agentRouter,
  todo: todoRouter,
});

export type AppRouter = typeof appRouter;
