import { db, todo as todoSchema } from "@stackpanel/db";
import { TRPCError } from "@trpc/server";
import { asc, eq } from "drizzle-orm";
import z from "zod";
import { publicProcedure, router } from "../index.old";

export const todoRouter = router({
	getAll: publicProcedure.query(
		async () =>
			await db.select().from(todoSchema.todo).orderBy(asc(todoSchema.todo.id)),
	),

	create: publicProcedure
		.input(z.object({ text: z.string().min(1) }))
		.mutation(async ({ input }) => {
			const result = await db
				.insert(todoSchema.todo)
				.values({
					text: input.text,
				})
				.returning();
			return result[0];
		}),

	toggle: publicProcedure
		.input(z.object({ id: z.number(), completed: z.boolean() }))
		.mutation(async ({ input }) => {
			const result = await db
				.update(todoSchema.todo)
				.set({ completed: input.completed })
				.where(eq(todoSchema.todo.id, input.id))
				.returning();

			if (result.length === 0) {
				throw new TRPCError({
					code: "NOT_FOUND",
					message: "Todo not found",
				});
			}

			return result[0];
		}),

	delete: publicProcedure
		.input(z.object({ id: z.number() }))
		.mutation(async ({ input }) => {
			const result = await db
				.delete(todoSchema.todo)
				.where(eq(todoSchema.todo.id, input.id))
				.returning();

			if (result.length === 0) {
				throw new TRPCError({
					code: "NOT_FOUND",
					message: "Todo not found",
				});
			}

			return result[0];
		}),
});
