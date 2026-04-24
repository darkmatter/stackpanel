import { getDb, subscription as subSchema } from "@stackpanel/db";
import { eq } from "drizzle-orm";

export type PlanId = "free" | "pro";

export type Entitlement = {
	plan: PlanId;
	status: string;
	/** True when `plan !== "free"` and `status ∈ {active, trialing}`. */
	paid: boolean;
	/** Current period end (null for free plans). */
	currentPeriodEnd: Date | null;
};

const PAID_STATUSES = new Set(["active", "trialing"]);
const PAID_PLANS: ReadonlySet<PlanId> = new Set(["pro"]);

/**
 * Resolve a user's current entitlement by reading the local subscription
 * mirror. Always returns — absence of a row means the user is on free.
 */
export async function getUserEntitlement(userId: string): Promise<Entitlement> {
	const rows = await getDb()
		.select()
		.from(subSchema.userSubscription)
		.where(eq(subSchema.userSubscription.userId, userId))
		.limit(1);

	const row = rows[0];
	if (!row) {
		return { plan: "free", status: "active", paid: false, currentPeriodEnd: null };
	}

	const plan = (row.plan as PlanId) ?? "free";
	const status = row.status;
	const paid = PAID_PLANS.has(plan) && PAID_STATUSES.has(status);

	return {
		plan,
		status,
		paid,
		currentPeriodEnd: row.currentPeriodEnd,
	};
}
