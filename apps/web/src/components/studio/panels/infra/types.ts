/**
 * Type definitions for SST infrastructure configuration.
 */

/** SST Data stored in .stack/data/sst.nix */
export type SSTData = {
	enable?: boolean;
	"project-name"?: string;
	region?: string;
	"account-id"?: string;
	"config-path"?: string;
	kms?: {
		enable?: boolean;
		alias?: string;
		"deletion-window-days"?: number;
	};
	oidc?: {
		provider?: string;
		"github-actions"?: {
			org?: string;
			repo?: string;
		};
		flyio?: {
			"org-id"?: string;
			"app-name"?: string;
		};
		"roles-anywhere"?: {
			"trust-anchor-arn"?: string;
		};
	};
	iam?: {
		"role-name"?: string;
	};
};

/** Runtime status from SST deployment */
export type SSTStatus = {
	configured: boolean;
	configPath: string;
	configValid: boolean;
	deployed: boolean;
	stage: string;
	lastDeploy?: string;
	outputs?: Record<string, unknown>;
	error?: string;
};

/** Deployed resource from SST stack */
export type SSTResource = {
	type: string;
	urn: string;
	id: string;
};
