import { TRPCError } from "@trpc/server";
import { eq } from "drizzle-orm";
import { z } from "zod/v4";

import { waitlist } from "@stackpanel/db";

import { createTRPCRouter, publicProcedure } from "../trpc";

const joinInput = z.object({
	email: z.email().max(254),
	name: z.string().trim().min(1).max(120).optional(),
	company: z.string().trim().max(120).optional(),
	role: z.string().trim().max(120).optional(),
	notes: z.string().trim().max(2000).optional(),
	source: z.string().trim().max(60).optional(),
	referrer: z.string().trim().max(2000).optional(),
});

function generateId(): string {
	const bytes = new Uint8Array(16);
	if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
		crypto.getRandomValues(bytes);
	} else {
		for (let i = 0; i < bytes.length; i++) {
			bytes[i] = Math.floor(Math.random() * 256);
		}
	}
	return Array.from(bytes)
		.map((b) => b.toString(16).padStart(2, "0"))
		.join("");
}

async function hashIp(ip: string | null | undefined): Promise<string | null> {
	if (!ip) return null;
	try {
		if (typeof crypto !== "undefined" && crypto.subtle) {
			const data = new TextEncoder().encode(ip);
			const digest = await crypto.subtle.digest("SHA-256", data);
			return Array.from(new Uint8Array(digest))
				.map((b) => b.toString(16).padStart(2, "0"))
				.join("")
				.slice(0, 32);
		}
	} catch {
		// fall through
	}
	return null;
}

export const waitlistRouter = createTRPCRouter({
	/**
	 * Join the beta waitlist. Idempotent on `email` — re-submitting with
	 * the same email returns `{ ok: true, alreadyOnList: true }` without
	 * mutating the existing row, so we don't lose attribution from the
	 * first signup.
	 */
	join: publicProcedure
		.input(joinInput)
		.mutation(async ({ ctx, input }) => {
			const email = input.email.trim().toLowerCase();

			const existing = await ctx.db
				.select({ id: waitlist.betaWaitlist.id })
				.from(waitlist.betaWaitlist)
				.where(eq(waitlist.betaWaitlist.email, email))
				.limit(1);

			if (existing.length > 0) {
				return { ok: true, alreadyOnList: true } as const;
			}

			const userAgent =
				ctx.headers?.get?.("user-agent") ?? ctx.headers?.get?.("User-Agent") ?? null;
			const forwarded = ctx.headers?.get?.("x-forwarded-for") ?? null;
			const ip = forwarded ? forwarded.split(",")[0]?.trim() ?? null : null;
			const ipHash = await hashIp(ip);

			try {
				await ctx.db.insert(waitlist.betaWaitlist).values({
					id: generateId(),
					email,
					name: input.name ?? null,
					company: input.company ?? null,
					role: input.role ?? null,
					source: input.source ?? null,
					notes: input.notes ?? null,
					referrer: input.referrer ?? null,
					userAgent,
					ipHash,
				});
			} catch (err) {
				if (
					err instanceof Error &&
					/duplicate key|unique constraint/i.test(err.message)
				) {
					return { ok: true, alreadyOnList: true } as const;
				}
				throw new TRPCError({
					code: "INTERNAL_SERVER_ERROR",
					message: "Could not save waitlist entry. Please try again.",
					cause: err,
				});
			}

			return { ok: true, alreadyOnList: false } as const;
		}),
});
