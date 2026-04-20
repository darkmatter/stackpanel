import { flattenEnvironmentVariables, getEnvironmentNames } from "@/components/studio/panels/apps/utils";

export const DEFAULT_APP_ENVIRONMENT_IDS = [
	"dev",
	"prod",
	"staging",
	"test",
] as const;

export interface FlattenedConfiguredAppVariable {
	envKey: string;
	value: string;
	environments: string[];
	isSecret: boolean;
	/**
	 * SOPS reference of the form "/<group>/<key>" identifying the secret value
	 * (e.g. "/dev/postgres-url" → group "dev", key "postgres-url"). The actual
	 * file lives at `<projectSecretsDir>/vars/<group>.sops.yaml`. Only set
	 * when the variable was declared with an explicit `sops` reference.
	 */
	sops?: string;
}

interface AppEnvVariableLike {
	key?: string;
	value?: string;
	defaultValue?: string;
	secret?: boolean;
	sops?: string;
}

interface AppEnvironmentLike {
	env?: Record<string, string>;
}

type AppEnvConfigLike = {
	env?: Record<string, AppEnvVariableLike>;
	environmentIds?: ReadonlyArray<string>;
	environments?: Record<string, AppEnvironmentLike>;
};

function normalizeEnvironmentId(env: string): string {
	if (env === "production") return "prod";
	if (env === "development") return "dev";
	return env;
}

export function getAppEnvironmentNames(
	app: AppEnvConfigLike,
): string[] {
	const explicit = Array.from(
		new Set(
			(app.environmentIds ?? [])
				.map((env) => normalizeEnvironmentId(String(env).trim()))
				.filter(Boolean),
		),
	);
	if (explicit.length > 0) return explicit;

	const legacy = getEnvironmentNames(app.environments);
	if (legacy.length > 0) return legacy;

	if (app.env && Object.keys(app.env).length > 0) {
		return [...DEFAULT_APP_ENVIRONMENT_IDS];
	}

	return [];
}

export function flattenConfiguredAppVariables(
	app: AppEnvConfigLike,
): FlattenedConfiguredAppVariable[] {
	const variables = new Map<string, FlattenedConfiguredAppVariable>();

	const configuredEnvironments = getAppEnvironmentNames(app);
	for (const [rawKey, rawVar] of Object.entries(app.env ?? {})) {
		const envKey = rawVar.key?.trim() || rawKey;
		const sopsRef = rawVar.sops?.trim() || undefined;
		variables.set(envKey, {
			envKey,
			value: rawVar.value ?? rawVar.defaultValue ?? "",
			environments: configuredEnvironments,
			isSecret: Boolean(rawVar.secret || sopsRef),
			sops: sopsRef,
		});
	}

	for (const mapping of flattenEnvironmentVariables(app.environments)) {
		const existing = variables.get(mapping.envKey);
		if (existing) {
			existing.environments = Array.from(
				new Set([...existing.environments, ...mapping.environments]),
			).sort();
			continue;
		}

		variables.set(mapping.envKey, {
			...mapping,
			isSecret: false,
		});
	}

	return Array.from(variables.values()).sort((a, b) =>
		a.envKey.localeCompare(b.envKey),
	);
}
