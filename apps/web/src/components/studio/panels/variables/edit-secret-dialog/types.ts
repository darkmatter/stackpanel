/**
 * Type definitions for secret editing components.
 */
import type { AgeIdentityResponse, KMSConfigResponse } from "@/lib/agent";

export interface EditSecretDialogProps {
	secretId: string;
	secretKey: string;
	description?: string;
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onSuccess: () => void;
}

export interface EditSecretDialogState {
	isLoading: boolean;
	isSaving: boolean;
	showValue: boolean;
	value: string;
	newDescription: string;
	identityPath: string;
	identityInfo: AgeIdentityResponse | null;
	showSettings: boolean;
	decryptError: string | null;
}

export interface AgeIdentitySettingsState {
	inputValue: string;
	identityInfo: AgeIdentityResponse | null;
	isLoading: boolean;
	isSaving: boolean;
	error: string | null;
}

export interface KMSSettingsState {
	kmsConfig: KMSConfigResponse | null;
	enabled: boolean;
	keyArn: string;
	awsProfile: string;
	isLoading: boolean;
	isSaving: boolean;
	error: string | null;
}
