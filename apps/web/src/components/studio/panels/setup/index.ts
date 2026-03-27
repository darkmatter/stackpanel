// Main wizard component

export { SetupProvider, useSetupContext } from "./setup-context";
export { SetupWizard } from "./setup-wizard";
// Components
export { StepCard } from "./step-card";
// Steps (for individual use or custom composition)
export {
	ConnectAgentStep,
	InitGroupsStep,
	InfrastructureStep,
	KmsConfigStep,
	ProjectInfoStep,
	SecretsBackendStep,
	TeamAccessStep,
	VerifyConfigStep,
} from "./steps";
// Types
export type {
	SetupContextValue,
	SetupStep,
	SSTData,
	SSTFormData,
	StepStatus,
} from "./types";
export { AWS_REGIONS, OIDC_PROVIDERS } from "./types";
