/**
 * Lightweight type re-exports and UI-friendly extensions.
 *
 * This file re-exports the proto-generated types and augments a few
 * UI-facing types used by the web app. Keep this file small and
 * intentionally stable to avoid frequent noise from proto regeneration.
 */

// Re-export proto-generated types
export * from "@stackpanel/proto";

// Import a couple of proto types used below
import type {
  App as ProtoApp,
  GeneratedFile as ProtoGeneratedFile,
} from "@stackpanel/proto";

// Re-export selected Nix-generated types (avoid wholesale re-exports to prevent name collisions)
export type {
  ServicesServices as Service,
  StackpanelDB as StackpanelConfig,
} from "./generated/nix-types";

// =============================================================================
// UI-friendly extensions
// =============================================================================

/** AppEntity - Extended App type with ID for UI usage. */
export interface AppEntity extends ProtoApp {
  id: string;
}

export type AppEntities = Record<string, AppEntity>;

/** Extended GeneratedFile with runtime status added by agent */
export interface GeneratedFileWithStatus extends ProtoGeneratedFile {
  existsOnDisk: boolean;
  isStale: boolean;
  size: number | null;
  contentHash: string | null;
}

export interface GeneratedFilesResponse {
  files: GeneratedFileWithStatus[];
  totalCount: number;
  staleCount: number;
  enabledCount: number;
  lastUpdated: string;
}

// =============================================================================
// Agent / API helper types (small subset used across the UI)
// =============================================================================

export interface ExecRequest {
  command: string;
  args?: string[];
  cwd?: string;
  env?: string[];
}

export interface ExecResult {
  exit_code: number;
  stdout: string;
  stderr: string;
}

export interface FileContent {
  path: string;
  content: string;
  exists: boolean;
}

export interface GenerateResult {
  success: boolean;
  output: string;
  error?: string;
}

export type SecretEnv = "dev" | "staging" | "prod";

export interface SetSecretRequest {
  env: SecretEnv;
  key: string;
  value: string;
}
export interface SetSecretResult {
  path: string;
}

// =============================================================================
// Group-based secrets (SOPS files per access control group)
// =============================================================================

/** Request to write a secret to a group's SOPS file */
export interface GroupSecretWriteRequest {
  /** Secret key name (e.g., DATABASE_URL) */
  key: string;
  /** Plaintext secret value to encrypt */
  value: string;
  /** Access control group (e.g., "dev", "prod", "ops") */
  group: string;
  /** Optional description */
  description?: string;
}

/** Response after writing a secret to a group */
export interface GroupSecretWriteResponse {
  /** The secret key that was written */
  key: string;
  /** The group the secret was written to */
  group: string;
  /** Relative path to the SOPS file (from project root) */
  path: string;
  /** Vals reference for source project configs (uses configured secrets dir) */
  valsRef: string;
  /** Vals reference for deployed env package (uses relative path: ref+sops://vars/<group>.sops.yaml#/<key>) */
  envPackageRef: string;
  /** Number of AGE recipients the file is encrypted to */
  recipientCount: number;
}

/** Request to read a secret from a group */
export interface GroupSecretReadRequest {
  /** Secret key to read */
  key: string;
  /** Access control group */
  group: string;
}

/** Response after reading a secret from a group */
export interface GroupSecretReadResponse {
  key: string;
  group: string;
  value: string;
}

/** Response listing secrets in a group */
export interface GroupSecretListResponse {
  group: string;
  keys: string[];
}

/** Response listing all groups and their keys */
export interface AllGroupsListResponse {
  groups: Record<string, string[]>;
}

/** Response from generating the env package */
export interface GenerateEnvPackageResponse {
  path: string;
  apps: number;
  groups: string[];
}

// =============================================================================
// Recipients & team access
// =============================================================================

/** A recipient who can decrypt secrets (has a .pub file in recipients dir) */
export interface Recipient {
  /** Recipient name (filename without .pub extension) */
  name: string;
  /** AGE public key */
  publicKey: string;
}

/** Response from listing recipients */
export interface RecipientListResponse {
  recipients: Recipient[];
}

/** Request to add a new recipient */
export interface AddRecipientRequest {
  /** Name for the recipient (used as filename) */
  name: string;
  /** AGE public key (starts with age1...) */
  publicKey?: string;
  /** SSH public key (will be converted to AGE via ssh-to-age) */
  sshPublicKey?: string;
}

/** Status of the GitHub Actions rekey workflow */
export interface RekeyWorkflowStatus {
  /** Whether the workflow file exists */
  exists: boolean;
  /** Path to the workflow file */
  path: string;
  /** Most recent workflow run info (if available) */
  lastRun?: {
    status: string;
    conclusion: string;
    createdAt: string;
  };
}

/** Request to verify secrets encrypt/decrypt round-trip */
export interface SecretsVerifyRequest {
  /** Group to verify (e.g., "dev") */
  group: string;
}

/** Response from secrets verification */
export interface SecretsVerifyResponse {
  /** Whether the round-trip succeeded */
  success: boolean;
  /** Error message if failed */
  error?: string;
}

/** Health information returned by the agent */
export interface AgentHealth {
  status: "available" | "unavailable" | "checking";
  projectRoot: string | null;
  hasProject: boolean;
  agentId: string | null;
  // computed convenience flag
  isPaired?: boolean;
}

// Nix data write request
export interface NixDataWriteRequest {
  entity: string;
  data: unknown;
}

// Nixpkgs search types
export interface NixpkgsPackage {
  name: string;
  attr_path: string;
  version: string;
  description: string;
  nixpkgs_url?: string;
  license?: string;
  homepage?: string;
  platforms?: string[];
  outputs?: string[];
  /** Whether this package is installed in the current devshell */
  installed?: boolean;
}

export interface NixpkgsSearchRequest {
  query: string;
  channel?: string;
  limit?: number;
  offset?: number;
}

export interface NixpkgsSearchResponse {
  packages: NixpkgsPackage[];
  total: number;
  query: string;
  channel: string;
}
