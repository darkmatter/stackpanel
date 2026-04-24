import { getDb, state as stateSchema } from "@stackpanel/db";
import { TRPCError } from "@trpc/server";
import { and, desc, eq } from "drizzle-orm";
import { z } from "zod/v4";
import {
	decryptForOrganization,
	encryptForOrganization,
} from "../lib/encryption";
import { createTRPCRouter, paidProcedure } from "../trpc";

/**
 * Hosted alchemy state backend router (Pro feature).
 *
 * Every procedure is gated on `paidProcedure`; free/expired users receive a
 * FORBIDDEN/402 error. Resources are scoped to the caller's active
 * organization — we never accept an arbitrary `organizationId` from the
 * client.
 */

const SLUG = /^[a-z0-9][a-z0-9-_.]{0,63}$/;
const stackInput = z.string().regex(SLUG, "Invalid stack name");
const stageInput = z.string().regex(SLUG, "Invalid stage name");
const fqnInput = z.string().min(1).max(256);

/**
 * Resolve the organization scope for this request. MVP: require the session
 * to have an active organization. Callers without one get a clear error
 * pointing them to switch or create one.
 */
function requireActiveOrg(session: { user: { id: string } } & { activeOrganizationId?: string | null }) {
	const orgId = session.activeOrganizationId;
	if (!orgId) {
		throw new TRPCError({
			code: "PRECONDITION_FAILED",
			message: "No active organization. Switch or create one before using hosted state.",
		});
	}
	return orgId;
}

export const alchemyStateRouter = createTRPCRouter({
	/**
	 * Fetch a single state entry — or null if it doesn't exist yet.
	 * Returns the decoded JSON payload and its current version (for optimistic
	 * concurrency on subsequent writes).
	 */
	get: paidProcedure
		.input(z.object({ stack: stackInput, stage: stageInput, fqn: fqnInput }))
		.query(async ({ ctx, input }) => {
			const organizationId = requireActiveOrg(ctx.session as never);
			const rows = await getDb()
				.select()
				.from(stateSchema.organizationState)
				.where(
					and(
						eq(stateSchema.organizationState.organizationId, organizationId),
						eq(stateSchema.organizationState.stack, input.stack),
						eq(stateSchema.organizationState.stage, input.stage),
						eq(stateSchema.organizationState.fqn, input.fqn),
					),
				)
				.limit(1);

			const row = rows[0];
			if (!row) return null;

			const plaintext = await decryptForOrganization(organizationId, {
				nonce: row.nonce,
				ciphertext: row.encryptedBlob,
			});
			return {
				version: row.version,
				updatedAt: row.updatedAt,
				payload: JSON.parse(plaintext),
			};
		}),

	/**
	 * Insert or update a state entry. Clients pass the version they last
	 * observed (0 for first write); a mismatch returns CONFLICT so callers
	 * can refetch + retry rather than silently clobbering a concurrent write.
	 */
	put: paidProcedure
		.input(
			z.object({
				stack: stackInput,
				stage: stageInput,
				fqn: fqnInput,
				expectedVersion: z.number().int().min(0),
				payload: z.unknown(),
			}),
		)
		.mutation(async ({ ctx, input }) => {
			const organizationId = requireActiveOrg(ctx.session as never);
			const plaintext = JSON.stringify(input.payload);
			const { nonce, ciphertext } = await encryptForOrganization(
				organizationId,
				plaintext,
			);

			const db = getDb();
			const existing = await db
				.select()
				.from(stateSchema.organizationState)
				.where(
					and(
						eq(stateSchema.organizationState.organizationId, organizationId),
						eq(stateSchema.organizationState.stack, input.stack),
						eq(stateSchema.organizationState.stage, input.stage),
						eq(stateSchema.organizationState.fqn, input.fqn),
					),
				)
				.limit(1);

			const prior = existing[0];
			if (prior) {
				if (prior.version !== input.expectedVersion) {
					throw new TRPCError({
						code: "CONFLICT",
						message: `Version mismatch: expected ${input.expectedVersion}, server is at ${prior.version}`,
						cause: { currentVersion: prior.version },
					});
				}
				const updated = await db
					.update(stateSchema.organizationState)
					.set({
						nonce,
						encryptedBlob: ciphertext,
						version: prior.version + 1,
					})
					.where(eq(stateSchema.organizationState.id, prior.id))
					.returning({ version: stateSchema.organizationState.version });
				return { version: updated[0]?.version ?? prior.version + 1 };
			}

			if (input.expectedVersion !== 0) {
				throw new TRPCError({
					code: "CONFLICT",
					message: `Entry does not exist — expectedVersion must be 0 for first write`,
					cause: { currentVersion: 0 },
				});
			}

			const inserted = await db
				.insert(stateSchema.organizationState)
				.values({
					id: crypto.randomUUID(),
					organizationId,
					stack: input.stack,
					stage: input.stage,
					fqn: input.fqn,
					nonce,
					encryptedBlob: ciphertext,
					version: 1,
				})
				.returning({ version: stateSchema.organizationState.version });
			return { version: inserted[0]?.version ?? 1 };
		}),

	/**
	 * List all entries in a stack+stage. Cheap — doesn't decrypt blobs.
	 * Use `get` to fetch individual payloads.
	 */
	list: paidProcedure
		.input(z.object({ stack: stackInput, stage: stageInput }))
		.query(async ({ ctx, input }) => {
			const organizationId = requireActiveOrg(ctx.session as never);
			const rows = await getDb()
				.select({
					fqn: stateSchema.organizationState.fqn,
					version: stateSchema.organizationState.version,
					updatedAt: stateSchema.organizationState.updatedAt,
				})
				.from(stateSchema.organizationState)
				.where(
					and(
						eq(stateSchema.organizationState.organizationId, organizationId),
						eq(stateSchema.organizationState.stack, input.stack),
						eq(stateSchema.organizationState.stage, input.stage),
					),
				)
				.orderBy(desc(stateSchema.organizationState.updatedAt));
			return rows;
		}),

	/**
	 * Delete a state entry. Version required so we don't race with a
	 * concurrent writer. Returns `{ deleted: true }` on success, throws NOT_FOUND
	 * if the entry doesn't exist.
	 */
	delete: paidProcedure
		.input(
			z.object({
				stack: stackInput,
				stage: stageInput,
				fqn: fqnInput,
				expectedVersion: z.number().int().min(1),
			}),
		)
		.mutation(async ({ ctx, input }) => {
			const organizationId = requireActiveOrg(ctx.session as never);
			const deleted = await getDb()
				.delete(stateSchema.organizationState)
				.where(
					and(
						eq(stateSchema.organizationState.organizationId, organizationId),
						eq(stateSchema.organizationState.stack, input.stack),
						eq(stateSchema.organizationState.stage, input.stage),
						eq(stateSchema.organizationState.fqn, input.fqn),
						eq(stateSchema.organizationState.version, input.expectedVersion),
					),
				)
				.returning({ id: stateSchema.organizationState.id });

			if (deleted.length === 0) {
				throw new TRPCError({
					code: "NOT_FOUND",
					message: "State entry not found or version mismatch",
				});
			}
			return { deleted: true };
		}),

	/**
	 * Enumerate the distinct stages that have state under a given stack.
	 * Used by the studio's state panel for the stage dropdown.
	 */
	listStages: paidProcedure
		.input(z.object({ stack: stackInput }))
		.query(async ({ ctx, input }) => {
			const organizationId = requireActiveOrg(ctx.session as never);
			const rows = await getDb()
				.selectDistinct({ stage: stateSchema.organizationState.stage })
				.from(stateSchema.organizationState)
				.where(
					and(
						eq(stateSchema.organizationState.organizationId, organizationId),
						eq(stateSchema.organizationState.stack, input.stack),
					),
				);
			return rows.map((r) => r.stage);
		}),
});
