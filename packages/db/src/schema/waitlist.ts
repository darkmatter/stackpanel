import { index, pgTable, text, timestamp, uniqueIndex } from "drizzle-orm/pg-core";

/**
 * Beta waitlist signups for the Stackpanel public launch.
 *
 * One row per email. Optional `source` tracks where the signup came from
 * (e.g. `landing.hero`, `landing.cta`, `pricing.team`) so we can attribute
 * which page was most effective. Optional `notes` captures the freeform
 * "what would you build?" answer when provided.
 */
export const betaWaitlist = pgTable(
	"beta_waitlist",
	{
		id: text("id").primaryKey(),
		email: text("email").notNull(),
		name: text("name"),
		company: text("company"),
		role: text("role"),
		source: text("source"),
		notes: text("notes"),
		referrer: text("referrer"),
		userAgent: text("user_agent"),
		ipHash: text("ip_hash"),
		invitedAt: timestamp("invited_at"),
		createdAt: timestamp("created_at").defaultNow().notNull(),
	},
	(table) => [
		uniqueIndex("beta_waitlist_email_uniq").on(table.email),
		index("beta_waitlist_created_idx").on(table.createdAt),
	],
);

export type BetaWaitlistRow = typeof betaWaitlist.$inferSelect;
export type NewBetaWaitlistRow = typeof betaWaitlist.$inferInsert;
