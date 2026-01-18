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
import type { App as ProtoApp, GeneratedFile as ProtoGeneratedFile } from "@stackpanel/proto";

// Re-export selected Nix-generated types (avoid wholesale re-exports to prevent name collisions)
export type { ServicesServices as Service, StackpanelDB as StackpanelConfig } from "./generated/nix-types";

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
