import {
	getDb,
	subscription as subSchema,
} from "@stackpanel/db";
import { eq } from "drizzle-orm";

/**
 * Polar product id → internal plan mapping. Decouples gating code from
 * Polar's product ids so we can rename / re-price without touching the
 * paidProcedure middleware.
 *
 * Override via env so different deploy stages can point at sandbox vs
 * production products without a code change.
 */
const PLAN_BY_PRODUCT: Record<string, "free" | "pro"> = {
	"5fb4014e-d879-4b28-966a-9efcf60b6c24": "pro",
	"70acf138-0b13-4fd0-8c25-78c63f09a122": "free",
};

function planForProduct(productId: string | undefined | null): "free" | "pro" {
	if (!productId) return "free";
	return PLAN_BY_PRODUCT[productId] ?? "free";
}

function resolveUserId(customer: {
	externalId?: string | null;
	metadata?: Record<string, unknown> | null;
}): string | null {
	if (customer.externalId) return customer.externalId;
	const metaUserId = customer.metadata?.userId;
	return typeof metaUserId === "string" ? metaUserId : null;
}

/**
 * Subscription fields we need. Narrower than the Polar SDK's Subscription
 * type — accepts structural shape instead of importing the SDK model, which
 * keeps us resilient to Polar adding fields without affecting our code.
 */
type SubscriptionShape = {
	id: string;
	status: string;
	productId?: string | null;
	currentPeriodEnd?: Date | string | null;
	cancelAtPeriodEnd?: boolean | null;
	customer: {
		id: string;
		externalId?: string | null;
		metadata?: Record<string, unknown> | null;
	};
};

type PayloadShape = {
	type: string;
	data: SubscriptionShape;
};

async function recordEvent(eventType: string, payload: PayloadShape) {
	// Polar's webhook dispatcher doesn't include the outer event id in the
	// per-event callbacks — use the subscription id + eventType as our
	// idempotency key. Good enough: same subscription cannot transition
	// through the same state twice.
	const key = `${eventType}:${payload.data.id}`;
	try {
		await getDb()
			.insert(subSchema.polarEvent)
			.values({
				id: crypto.randomUUID(),
				polarEventId: key,
				eventType,
				payload: JSON.stringify(payload),
			})
			.onConflictDoNothing();
	} catch (error) {
		console.error("[polar-webhooks] failed to record event", { key, error });
	}
}

async function upsertFromSubscription(
	sub: SubscriptionShape,
	overrides: Partial<{ plan: "free" | "pro"; status: string }> = {},
) {
	const userId = resolveUserId(sub.customer);
	if (!userId) {
		console.warn("[polar-webhooks] subscription without mappable user", {
			subscriptionId: sub.id,
			customerId: sub.customer.id,
		});
		return;
	}

	const plan = overrides.plan ?? planForProduct(sub.productId);
	const status = overrides.status ?? sub.status;
	const currentPeriodEnd = sub.currentPeriodEnd
		? new Date(sub.currentPeriodEnd)
		: null;
	const cancelAtPeriodEnd = sub.cancelAtPeriodEnd != null
		? String(sub.cancelAtPeriodEnd)
		: null;

	const db = getDb();
	const existing = await db
		.select({ id: subSchema.userSubscription.id })
		.from(subSchema.userSubscription)
		.where(eq(subSchema.userSubscription.userId, userId))
		.limit(1);

	if (existing[0]) {
		await db
			.update(subSchema.userSubscription)
			.set({
				polarCustomerId: sub.customer.id,
				polarSubscriptionId: sub.id,
				plan,
				status,
				currentPeriodEnd,
				cancelAtPeriodEnd,
			})
			.where(eq(subSchema.userSubscription.id, existing[0].id));
	} else {
		await db.insert(subSchema.userSubscription).values({
			id: crypto.randomUUID(),
			userId,
			polarCustomerId: sub.customer.id,
			polarSubscriptionId: sub.id,
			plan,
			status,
			currentPeriodEnd,
			cancelAtPeriodEnd,
		});
	}
}

/**
 * Callbacks bundle passed to the Polar `webhooks` plugin.
 *
 * We accept each handler's payload as `any` internally — the Polar SDK
 * validates structure before calling us, and the types are a sprawling
 * discriminated union we don't want to couple to. The private
 * SubscriptionShape constrains what we actually read.
 */
export function polarSubscriptionCallbacks() {
	const asSub = (p: unknown): PayloadShape => p as PayloadShape;

	return {
		onSubscriptionCreated: async (payload: unknown) => {
			const event = asSub(payload);
			await recordEvent("subscription.created", event);
			await upsertFromSubscription(event.data);
		},
		onSubscriptionActive: async (payload: unknown) => {
			const event = asSub(payload);
			await recordEvent("subscription.active", event);
			await upsertFromSubscription(event.data, { status: "active" });
		},
		onSubscriptionUpdated: async (payload: unknown) => {
			const event = asSub(payload);
			await recordEvent("subscription.updated", event);
			await upsertFromSubscription(event.data);
		},
		onSubscriptionUncanceled: async (payload: unknown) => {
			const event = asSub(payload);
			await recordEvent("subscription.uncanceled", event);
			await upsertFromSubscription(event.data);
		},
		onSubscriptionCanceled: async (payload: unknown) => {
			// Polar "canceled" usually means cancel_at_period_end=true — the
			// user retains access until currentPeriodEnd. Keep plan unchanged;
			// flip to free only on `revoked`.
			const event = asSub(payload);
			await recordEvent("subscription.canceled", event);
			await upsertFromSubscription(event.data, { status: "canceled" });
		},
		onSubscriptionRevoked: async (payload: unknown) => {
			// Access terminated (period ended after cancellation, or admin
			// revoke). Downgrade to free.
			const event = asSub(payload);
			await recordEvent("subscription.revoked", event);
			await upsertFromSubscription(event.data, {
				plan: "free",
				status: "revoked",
			});
		},
	};
}
