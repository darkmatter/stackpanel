/**
 * Polar product IDs keyed by deploy environment.
 *
 * Single source of truth so the Better-Auth checkout plugin and the
 * webhook handler agree on which Polar product maps to which internal
 * plan. Production IDs come from env at runtime — sandbox IDs are hard-
 * coded so local dev and preview builds work without secrets configured.
 *
 * Environment resolution:
 *   STACKPANEL_DEPLOY_ENV = "dev" | "preview" | "production"
 *   (falls back to "dev" for unset / unrecognized values)
 */

export type DeployEnv = "dev" | "preview" | "production";
export type PlanId = "pro" | "free";

const SANDBOX_PRO = "5fb4014e-d879-4b28-966a-9efcf60b6c24";
const SANDBOX_FREE = "70acf138-0b13-4fd0-8c25-78c63f09a122";

/**
 * Product IDs per env. Production values are overridden at runtime by
 * POLAR_PRO_PRODUCT_ID_PRODUCTION / POLAR_FREE_PRODUCT_ID_PRODUCTION —
 * those are the *only* values that should ever live in production Fly
 * secrets. Dev + preview stay on the sandbox IDs so preview deploys
 * don't charge real cards.
 */
export function polarProducts(
	env: DeployEnv = resolveDeployEnv(),
): Record<PlanId, string> {
	switch (env) {
		case "production":
			return {
				pro: process.env.POLAR_PRO_PRODUCT_ID_PRODUCTION ?? SANDBOX_PRO,
				free: process.env.POLAR_FREE_PRODUCT_ID_PRODUCTION ?? SANDBOX_FREE,
			};
		case "preview":
		case "dev":
		default:
			return { pro: SANDBOX_PRO, free: SANDBOX_FREE };
	}
}

export function resolveDeployEnv(): DeployEnv {
	const raw = (
		process.env.STACKPANEL_DEPLOY_ENV ??
		process.env.DEPLOY_ENV ??
		process.env.NODE_ENV ??
		"dev"
	).toLowerCase();
	if (raw === "production" || raw === "prod") return "production";
	if (raw === "preview" || raw === "staging") return "preview";
	return "dev";
}

/**
 * Inverse lookup: given a Polar product id, return the internal plan.
 * Used by the webhook handler to translate product-id payloads into plan
 * claims without coupling to any specific env.
 *
 * Walks all envs so a subscription opened against a sandbox product in
 * dev still resolves correctly if the webhook hits production (e.g.,
 * a customer migrated to prod mid-cycle).
 */
export function planForProduct(productId: string | null | undefined): PlanId | "unknown" {
	if (!productId) return "unknown";
	const envs: DeployEnv[] = ["production", "preview", "dev"];
	for (const env of envs) {
		const products = polarProducts(env);
		for (const [plan, id] of Object.entries(products) as [PlanId, string][]) {
			if (id === productId) return plan;
		}
	}
	return "unknown";
}
