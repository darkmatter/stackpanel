/**
 * Type definitions for secret editing components.
 *
 * Supports group-based SOPS secrets for access control.
 * Secrets are stored in SOPS files per group, and the variable value
 * becomes a vals reference: ref+sops://.stackpanel/secrets/groups/<group>.yaml#/<key>
 */
import type { AgeIdentityResponse, KMSConfigResponse } from "@/lib/agent";

export interface EditSecretDialogProps {
  /** Secret identifier (for legacy .age file based secrets) */
  secretId: string;
  /** Environment variable key name (e.g., DATABASE_URL) */
  secretKey: string;
  /** Access control group (e.g., "dev", "prod", "ops") */
  group?: string;
  /** Optional description of the secret */
  description?: string;
  /** Whether the dialog is open */
  open: boolean;
  /** Callback when dialog open state changes */
  onOpenChange: (open: boolean) => void;
  /**
   * Callback when secret is saved successfully.
   * @param valsRef - The vals reference to use in app configs (for group-based secrets)
   */
  onSuccess: (valsRef?: string) => void;
}

export interface EditSecretDialogState {
  isLoading: boolean;
  isSaving: boolean;
  showValue: boolean;
  value: string;
  newDescription: string;
  /** Selected group for access control */
  group: string;
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

/** Available groups for secrets access control */
export interface SecretsGroup {
  /** Group name (e.g., "dev", "prod") */
  name: string;
  /** Whether the group has been initialized with keys */
  initialized: boolean;
  /** Number of secrets in this group */
  secretCount?: number;
}
