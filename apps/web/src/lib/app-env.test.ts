import { describe, expect, it } from "vite-plus/test";
import {
	DEFAULT_APP_ENVIRONMENT_IDS,
	flattenConfiguredAppVariables,
	getAppEnvironmentNames,
} from "./app-env";

describe("app-env", () => {
	it("defaults app env variables to the standard environment ids", () => {
		const app = {
			env: {
				PORT: {
					value: "3000",
				},
			},
		};

		expect(getAppEnvironmentNames(app as never)).toEqual(
			DEFAULT_APP_ENVIRONMENT_IDS,
		);
	});

	it("flattens configured app env variables from app.env", () => {
		const app = {
			env: {
				PORT: {
					value: "3000",
				},
				DATABASE_URL: {
					sops: "/dev/database-url",
					secret: true,
				},
			},
			environmentIds: ["development", "production"],
		};

		expect(flattenConfiguredAppVariables(app as never)).toEqual([
			{
				envKey: "DATABASE_URL",
				value: "",
				environments: ["dev", "prod"],
				isSecret: true,
				sops: "/dev/database-url",
			},
			{
				envKey: "PORT",
				value: "3000",
				environments: ["dev", "prod"],
				isSecret: false,
				sops: undefined,
			},
		]);
	});

	it("falls back to deprecated app.environments when app.env is absent", () => {
		const app = {
			environments: {
				dev: {
					name: "dev",
					env: {
						PORT: "3000",
					},
				},
			},
		};

		expect(flattenConfiguredAppVariables(app as never)).toEqual([
			{
				envKey: "PORT",
				value: "3000",
				environments: ["dev"],
				isSecret: false,
			},
		]);
	});

	it("preserves the sops reference even when secret is not explicitly set", () => {
		const app = {
			env: {
				API_TOKEN: {
					sops: "/shared/api-token",
				},
			},
			environmentIds: ["dev"],
		};

		const flat = flattenConfiguredAppVariables(app as never);
		expect(flat).toHaveLength(1);
		expect(flat[0]).toMatchObject({
			envKey: "API_TOKEN",
			isSecret: true,
			sops: "/shared/api-token",
		});
	});
});
