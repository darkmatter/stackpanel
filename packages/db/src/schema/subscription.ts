import { relations } from "drizzle-orm";
import { index, pgTable, text, timestamp, uniqueIndex } from "drizzle-orm/pg-core";
import { user } from "./auth";

/**
 * Per-user subscription mirror for Polar.
 *
 * Populated by the Polar webhook handler on subscription lifecycle events.
 * Queried by `protectedPaidProcedure` to gate cloud features cheaply without
 * a round-trip to Polar on every API call.
 *
 * `plan` is a stable internal identifier ("free" | "pro") — NOT the Polar
 * product id. Webhook translates Polar products → plan identifiers, so we can
 * change Polar product ids without rewriting gating logic.
 *
 * `status` follows Polar's subscription states: active, trialing, canceled,
 * past_due, incomplete, incomplete_expired, unpaid. Only `active` and
 * `trialing` grant paid access.
 */
export const userSubscription = pgTable(
	"user_subscription",
	{
		id: text("id").primaryKey(),
		userId: text("user_id")
			.notNull()
			.references(() => user.id, { onDelete: "cascade" }),
		polarCustomerId: text("polar_customer_id").notNull(),
		polarSubscriptionId: text("polar_subscription_id"),
		plan: text("plan").notNull().default("free"),
		status: text("status").notNull().default("active"),
		currentPeriodEnd: timestamp("current_period_end"),
		cancelAtPeriodEnd: text("cancel_at_period_end"),
		createdAt: timestamp("created_at").defaultNow().notNull(),
		updatedAt: timestamp("updated_at")
			.defaultNow()
			.$onUpdate(() => /* @__PURE__ */ new Date())
			.notNull(),
	},
	(table) => [
		uniqueIndex("user_subscription_user_idx").on(table.userId),
		index("user_subscription_polar_customer_idx").on(table.polarCustomerId),
	],
);

/**
 * Polar webhook event log — every webhook we process produces a row here.
 * Used for idempotency (dedupe on polar_event_id) and audit/debugging.
 */
export const polarEvent = pgTable(
	"polar_event",
	{
		id: text("id").primaryKey(),
		polarEventId: text("polar_event_id").notNull(),
		eventType: text("event_type").notNull(),
		payload: text("payload").notNull(),
		processedAt: timestamp("processed_at").defaultNow().notNull(),
	},
	(table) => [uniqueIndex("polar_event_polar_id_idx").on(table.polarEventId)],
);

export const userSubscriptionRelations = relations(userSubscription, ({ one }) => ({
	user: one(user, {
		fields: [userSubscription.userId],
		references: [user.id],
	}),
}));
