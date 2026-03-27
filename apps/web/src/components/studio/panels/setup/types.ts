import type { ReactNode } from "react";

// =============================================================================
// Step Types
// =============================================================================

export type StepStatus =
	| "complete"
	| "incomplete"
	| "in-progress"
	| "optional"
	| "blocked";

export interface SetupStep {
	id: string;
	title: string;
	description: string;
	status: StepStatus;
	required: boolean;
	dependsOn?: string[];
	icon: ReactNode;
}

// =============================================================================
// SST Data Types
// =============================================================================

export interface SSTData {
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
		"github-actions"?: { org?: string; repo?: string; branch?: string };
		flyio?: { "org-id"?: string; "app-name"?: string };
		"roles-anywhere"?: { "trust-anchor-arn"?: string };
	};
	iam?: {
		"role-name"?: string;
	};
}

// SSTFormData mirrors SSTData for form state
export type SSTFormData = SSTData;

// =============================================================================
// AWS Constants
// =============================================================================

export const AWS_REGIONS = [
	{ value: "us-east-1", label: "US East (N. Virginia)" },
	{ value: "us-east-2", label: "US East (Ohio)" },
	{ value: "us-west-1", label: "US West (N. California)" },
	{ value: "us-west-2", label: "US West (Oregon)" },
	{ value: "eu-west-1", label: "Europe (Ireland)" },
	{ value: "eu-west-2", label: "Europe (London)" },
	{ value: "eu-central-1", label: "Europe (Frankfurt)" },
	{ value: "ap-northeast-1", label: "Asia Pacific (Tokyo)" },
	{ value: "ap-southeast-1", label: "Asia Pacific (Singapore)" },
	{ value: "ap-southeast-2", label: "Asia Pacific (Sydney)" },
];

export const OIDC_PROVIDERS = [
	{
		value: "github-actions",
		label: "GitHub Actions",
		description: "CI/CD from GitHub repositories",
	},
	{
		value: "flyio",
		label: "Fly.io",
		description: "Deploy from Fly.io Machines",
	},
	{
		value: "roles-anywhere",
		label: "AWS Roles Anywhere",
		description: "Certificate-based authentication",
	},
	{ value: "none", label: "None", description: "No OIDC provider" },
];

// =============================================================================
// Step Context
// =============================================================================

export interface SetupContextValue {
	// Navigation
	expandedStep: string | null;
	setExpandedStep: (step: string | null) => void;
	goToStep: (stepId: string) => void;

	// Agent
	isConnected: boolean;
	token: string | null;

	// Project info
	projectName: string;
	githubRepo: string;
	homeDirPath: string;
	dataPath: string;
	genPath: string;
	statePath: string;
	projectConfirmed: boolean;
	confirmProject: () => void;

	// AWS/SST
	sstData: SSTData | null;
	sstFormData: SSTFormData;
	setSstFormData: React.Dispatch<React.SetStateAction<SSTFormData>>;
	handleSaveSST: () => Promise<void>;
	sstSaving: boolean;
	hasAwsKms: boolean;

	// Groups
	groupsInitialized: Record<string, boolean>;
	setGroupsInitialized: React.Dispatch<
		React.SetStateAction<Record<string, boolean>>
	>;
	groupsVerified: Record<string, boolean>;
	setGroupsVerified: React.Dispatch<
		React.SetStateAction<Record<string, boolean>>
	>;

	// Recipients/Team
	recipientsCount: number;

	// KMS
	kmsConfig: { enable?: boolean } | null;

	// Config verification
	configVerified: boolean;
	setConfigVerified: React.Dispatch<React.SetStateAction<boolean>>;

	// Secrets backend (chamber = AWS SSM, detected from Nix config)
	isChamber: boolean;
}
