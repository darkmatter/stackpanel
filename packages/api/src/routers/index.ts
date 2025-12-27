import { protectedProcedure, publicProcedure, router } from "../index.old";
import { todoRouter } from "./todo";

export const appRouter = router({
	healthCheck: publicProcedure.query(() => "OK"),
	privateData: protectedProcedure.query(({ ctx }) => ({
		message: "This is private",
		user: ctx.session.user,
	})),
	todo: todoRouter,
});
export type AppRouter = typeof appRouter;
