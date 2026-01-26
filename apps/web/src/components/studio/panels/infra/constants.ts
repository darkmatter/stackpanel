/**
 * Constants for SST infrastructure configuration.
 */
import type { SSTData } from "./types";

export const OIDC_PROVIDERS = [
	{ value: "github-actions", label: "GitHub Actions" },
	{ value: "flyio", label: "Fly.io" },
	{ value: "roles-anywhere", label: "AWS Roles Anywhere" },
	{ value: "none", label: "None" },
] as const;

export const AWS_REGIONS = [
	"us-east-1",
	"us-east-2",
	"us-west-1",
	"us-west-2",
	"eu-west-1",
	"eu-west-2",
	"eu-central-1",
	"ap-northeast-1",
	"ap-southeast-1",
	"ap-southeast-2",
] as const;

export const DEFAULT_SST_DATA: SSTData = {
	enable: false,
	"project-name": "",
	region: "us-west-2",
	"account-id": "",
	"config-path": "packages/infra/sst.config.ts",
	kms: {
		enable: true,
		alias: "",
		"deletion-window-days": 30,
	},
	oidc: {
		provider: "github-actions",
		"github-actions": { org: "", repo: "*" },
		flyio: { "org-id": "", "app-name": "*" },
		"roles-anywhere": { "trust-anchor-arn": "" },
	},
	iam: {
		"role-name": "",
	},
};

/** Merge SST data with defaults for complete object */
export function mergeWithDefaults(data: SSTData): SSTData {
	return {
		...DEFAULT_SST_DATA,
		...data,
		kms: { ...DEFAULT_SST_DATA.kms, ...data.kms },
		oidc: {
			...DEFAULT_SST_DATA.oidc,
			...data.oidc,
			"github-actions": {
				...DEFAULT_SST_DATA.oidc?.["github-actions"],
				...data.oidc?.["github-actions"],
			},
			flyio: {
				...DEFAULT_SST_DATA.oidc?.flyio,
				...data.oidc?.flyio,
			},
			"roles-anywhere": {
				...DEFAULT_SST_DATA.oidc?.["roles-anywhere"],
				...data.oidc?.["roles-anywhere"],
			},
		},
		iam: { ...DEFAULT_SST_DATA.iam, ...data.iam },
	};
}
