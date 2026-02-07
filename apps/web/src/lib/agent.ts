import {
  kebabToSnake,
  kebabToSnakeValues,
  snakeToKebab,
  snakeToKebabValues,
} from "./nix-data";
import type {
  App,
  Variable,
  GeneratedFile,
  GeneratedFilesResponse,
  Service,
  Task,
  User,
  AgentHealth,
  ExecRequest,
  ExecResult,
  GenerateResult,
  FileContent,
  SetSecretRequest,
  SetSecretResult,
  GroupSecretWriteRequest,
  GroupSecretWriteResponse,
  GroupSecretReadRequest,
  GroupSecretReadResponse,
  GroupSecretListResponse,
  AllGroupsListResponse,
  GenerateEnvPackageResponse,
} from "./types";

// The full Nix config is a dynamic object from nix eval, not the proto Config message
// Use a generic record type since it contains apps, extensions, and many other fields
export type NixConfig = Record<string, unknown>;

// =============================================================================
// Nix Data API Types (from nix-client.ts)
// =============================================================================

export interface DataResponse<T> {
  data: T | null;
  exists: boolean;
  success: boolean;
  error?: string;
}

export interface ListResponse<T> {
  data: T[];
  success: boolean;
  error?: string;
}

export interface WriteResponse {
  success: boolean;
  path: string;
  error?: string;
}

export interface DeleteResponse {
  success: boolean;
  path: string;
  error?: string;
}

/**
 * EntityClient - CRUD client for a specific Nix entity file.
 * (Currently unused but kept for future use)
 */
class _EntityClient<T> {
  constructor(
    private client: AgentHttpClient,
    private entityName: string,
  ) {}

  async get(): Promise<T | null> {
    // API returns { success, data: { entity, exists, data } }
    const apiRes = await this.client.get<{
      success: boolean;
      data: DataResponse<T>;
    }>(`/api/nix/data?entity=${encodeURIComponent(this.entityName)}`);
    const res = apiRes.data;
    return res.exists && res.data ? kebabToSnake(res.data) : null;
  }

  async set(data: T): Promise<WriteResponse> {
    return this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      data: snakeToKebab(data),
    });
  }

  async update(updates: Partial<T>): Promise<WriteResponse> {
    const current = await this.get();
    return this.set({ ...(current ?? ({} as T)), ...updates });
  }

  async delete(): Promise<DeleteResponse> {
    return this.client.delete<DeleteResponse>(
      `/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
    );
  }
}

/**
 * MapEntityClient - CRUD client for Nix entities stored as maps (e.g., apps, variables).
 */
class MapEntityClient<V> {
  constructor(
    private client: AgentHttpClient,
    private entityName: string,
  ) {}

  async all(): Promise<Record<string, V>> {
    // API returns { success, data: { entity, exists, data } }
    const apiRes = await this.client.get<{
      success: boolean;
      data: DataResponse<Record<string, V>>;
    }>(`/api/nix/data?entity=${encodeURIComponent(this.entityName)}`);
    const res = apiRes.data;
    return res.exists && res.data ? kebabToSnakeValues(res.data) : {};
  }

  async get(key: string): Promise<V | null> {
    const all = await this.all();
    return all[key] ?? null;
  }

  async set(key: string, value: V): Promise<WriteResponse> {
    // Use key-level update to avoid overwriting computed variables
    return this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      key: key,
      data: snakeToKebabValues({ [key]: value })[key],
    });
  }

  async update(key: string, updates: Partial<V>): Promise<WriteResponse> {
    // First get the current value for this key only
    const current = await this.get(key);
    const merged = { ...(current ?? {}), ...updates } as V;
    return this.set(key, merged);
  }

  async remove(key: string): Promise<WriteResponse> {
    // Use key-level delete
    return this.client.post<WriteResponse>("/api/nix/data", {
      entity: this.entityName,
      key: key,
      delete: true,
    });
  }

  async deleteAll(): Promise<DeleteResponse> {
    return this.client.delete<DeleteResponse>(
      `/api/nix/data?entity=${encodeURIComponent(this.entityName)}`,
    );
  }
}

/** Request to write an age-encrypted secret using agenix */
export interface AgenixSecretRequest {
  /** Unique identifier for the secret (used as filename: <id>.age) */
  id: string;
  /** Environment variable name (e.g., DATABASE_URL) */
  key: string;
  /** Plaintext secret value to encrypt */
  value: string;
  /** Optional description */
  description?: string;
  /** Environments this secret is available in (empty = all) */
  environments?: string[];
}

/** Response from writing an agenix secret */
export interface AgenixSecretResponse {
  id: string;
  path: string;
  agePath: string;
  keyCount: number;
}

/** Request to decrypt an age-encrypted secret */
export interface AgenixDecryptRequest {
  /** Secret identifier (matches filename without .age extension) */
  id: string;
  /** Path to AGE private key file (optional, uses default locations if not specified) */
  identityPath?: string;
}

/** Response from decrypting a secret */
export interface AgenixDecryptResponse {
  id: string;
  value: string;
}

/** Response from age identity operations */
export interface AgeIdentityResponse {
  /** Type is either "path", "key", or "" (not configured) */
  type: "" | "path" | "key";
  /** Value is the path (if type=path) or "(key stored)" (if type=key) */
  value: string;
  /** KeyPath is the actual file path used for decryption */
  keyPath: string;
}

/** Request to set KMS configuration */
export interface KMSConfigRequest {
  enable: boolean;
  keyArn: string;
  awsProfile?: string;
}

/** Response from KMS config operations */
export interface KMSConfigResponse {
  enable: boolean;
  keyArn: string;
  awsProfile: string;
  /** Source is "state" if from state file, empty if not configured */
  source: "" | "state" | "nix";
}

/** Response from reading SOPS secrets for an environment */
export interface SopsSecretsReadResponse {
  exists: boolean;
  path: string;
  encrypted?: boolean;
  secrets: Record<string, unknown>;
  raw?: string;
  error?: string;
}

/** Response from listing SOPS environments and their key names */
export interface SopsSecretsListResponse {
  environments: Record<string, string[]>;
}

// SST Infrastructure types

/** SST configuration from Nix */
export interface SSTConfig {
  enable: boolean;
  "project-name": string;
  region: string;
  "account-id": string;
  "config-path": string;
  kms: {
    enable: boolean;
    alias: string;
  };
  oidc: {
    provider: string;
    "github-actions": {
      org: string;
      repo: string;
    };
    flyio: {
      "org-id": string;
      "app-name": string;
    };
    "roles-anywhere": {
      "trust-anchor-arn": string;
    };
  };
  iam: {
    "role-name": string;
  };
}

/** SST deployment status */
export interface SSTStatus {
  configured: boolean;
  configPath: string;
  configValid: boolean;
  deployed: boolean;
  stage: string;
  lastDeploy?: string;
  outputs?: Record<string, unknown>;
  error?: string;
}

/** SST deployed resource */
export interface SSTResource {
  type: string;
  urn: string;
  id: string;
}

// Module requirements types (from Nix moduleRequirements config)

/** Project validation response */
export interface ProjectValidateResponse {
  valid: boolean;
  error?: string;
  message?: string;
}

/** Action to resolve a missing variable */
export interface VariableAction {
  type: string;
  label: string;
  url?: string | null;
}

/** A required variable declared by a module */
export interface ModuleRequiredVariable {
  key: string;
  description: string;
  sensitive: boolean;
  action?: VariableAction | null;
}

/** Requirements declared by a single module */
export interface ModuleRequirements {
  requires: ModuleRequiredVariable[];
  provides: string[];
}

/** All module requirements from config */
export type AllModuleRequirements = Record<string, ModuleRequirements>;

/** SST deploy response */
export interface SSTDeployResponse {
  success: boolean;
  output: string;
  error?: string;
  outputs?: Record<string, unknown>;
}

/** ProcessInfo represents information about a running process from process-compose. */
export interface ProcessInfo {
  name: string;
  namespace?: string;
  status: string;
  pid?: number;
  exit_code?: number;
  is_running: boolean;
  restarts?: number;
  system_time?: string;
}

/** ProcessComposeStatusResponse represents the response from the processes endpoint. */
export interface ProcessComposeStatusResponse {
  available: boolean;
  running: boolean;
  processes: ProcessInfo[];
  error?: string;
}

/** ProjectState represents the project state from process-compose. */
export interface ProcessComposeProjectState {
  available: boolean;
  state?: Record<string, unknown>;
  error?: string;
}

/** ProcessPorts represents ports used by a process. */
export interface ProcessPorts {
  name: string;
  tcpPorts?: number[];
  udpPorts?: number[];
}

/** ProcessLogs represents log output from a process. */
export interface ProcessLogs {
  logs: string[];
}

/** LogMessage represents a single log message for WebSocket streaming. */
export interface LogMessage {
  processName: string;
  message: string;
}

/** Installed package information from devenv/stackpanel config */
export interface InstalledPackageInfo {
  name: string;
  version?: string;
  attrPath?: string;
  source?: "devshell" | "user";
}

/** Response from /api/nixpkgs/installed endpoint */
export interface InstalledPackagesResponse {
  packages: InstalledPackageInfo[];
  count: number;
}

/** Nixpkgs package for search results */
export interface NixpkgsPackage {
  name: string;
  attr_path: string;
  version: string;
  description: string;
  installed: boolean;
  license?: string;
  homepage?: string;
  nixpkgs_url: string;
}

/** Task from turbo query */
export interface TurboTask {
  name: string;
}

/** Package node from turbo packageGraph query */
export interface TurboPackage {
  /** Package name (e.g., "//", "@stackpanel/api", "web") */
  name: string;
  /** Package path relative to root */
  path: string;
  /** Tasks available for this package */
  tasks: TurboTask[];
}

/** Result type for turbo query { packageGraph { nodes { items { name path tasks { items { name } } } } } } */
export interface TurboPackageGraphResult {
  data: {
    packageGraph: {
      nodes: {
        items: Array<{
          name: string;
          path: string;
          tasks: {
            items: Array<{ name: string }>;
          };
        }>;
      };
    };
  };
}

/** Project information from the agent */
export interface Project {
  id?: string;
  path: string;
  name: string;
  last_opened?: string;
  active?: boolean;
  is_default?: boolean;
}

/** Response from /api/project/current */
export interface ProjectCurrentResponse {
  has_project: boolean;
  project: Project | null;
  default_project?: Project | null;
}

/** Response from /api/project/open */
export interface ProjectOpenResponse {
  success: boolean;
  project: Project;
  devshell?: {
    in_devshell: boolean;
    has_devshell_env: boolean;
    error?: string;
  };
}

/** Options for getPackages method */
export interface GetPackagesOptions {
  /** Exclude the root package "//" from results */
  excludeRoot?: boolean;
}

/** Options for getPackageGraph method */
export interface GetPackageGraphOptions {
  /** Exclude the root package "//" from results */
  excludeRoot?: boolean;
}

// =============================================================================
// Auth Error Event
// =============================================================================

/**
 * Custom event name dispatched when the agent returns a 401 Unauthorized.
 * The AgentProvider listens for this and triggers re-pairing.
 */
export const AGENT_AUTH_ERROR_EVENT = "stackpanel:auth-error";

/**
 * Dispatch a global auth error event. Called on any 401 response from the agent.
 * This allows the AgentProvider to clear the invalid token and show the pairing UI.
 */
function dispatchAuthError() {
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent(AGENT_AUTH_ERROR_EVENT));
  }
}

/**
 * HTTP client to interact with the StackPanel agent.
 */
export interface AgentHttpClientConfig {
  host?: string;
  port?: number;
  token?: string;
  /** Project ID, name, or path to use for requests */
  projectId?: string;
}

export class AgentHttpClient {
  private baseUrl: string;
  private token?: string;
  private projectId?: string;

  // Nix configuration data clients
  public readonly nix = {
    apps: new MapEntityClient<App>(this, "apps"),
    services: new MapEntityClient<Service>(this, "services"),
    users: new MapEntityClient<User>(this, "users"),
    generatedFiles: new MapEntityClient<GeneratedFile>(this, "generated-files"),
    variables: new MapEntityClient<Variable>(this, "variables"),
    tasks: new MapEntityClient<Task>(this, "tasks"),

    /** Generic entity client for custom paths */
    entity: <T>(name: string) => new MapEntityClient<T>(this, name),

    /** Alias for entity() to maintain compatibility with NixClient */
    mapEntity: <T>(name: string) => new MapEntityClient<T>(this, name),

    /** Get the full Nix configuration */
    config: async (options: { refresh?: boolean } = {}): Promise<NixConfig> => {
      const response = await this.get<{
        success: boolean;
        data: {
          config: NixConfig;
          last_updated: string;
          cached: boolean;
          source: string;
        };
      }>(`/api/nix/config${options.refresh ? "?refresh=true" : ""}`);
      // Extract config from the API wrapper response
      return response.data.config;
    },

    /** Force a re-evaluation of the Nix config */
    refreshConfig: async (): Promise<NixConfig> => {
      const response = await this.post<{
        success: boolean;
        data: {
          config: NixConfig;
          last_updated: string;
          refreshed: boolean;
          source: string;
        };
      }>("/api/nix/config", {});
      // Extract config from the API wrapper response
      return response.data.config;
    },
  };

  /**
   * Create an AgentHttpClient.
   * @param configOrHost - Either a config object { host?, port?, token? } or host string
   * @param port - Port number (only used if first arg is a string)
   * @param token - Auth token (only used if first arg is a string)
   */
  constructor(
    configOrHost: AgentHttpClientConfig | string = {},
    port = 9876,
    token?: string,
  ) {
    if (typeof configOrHost === "string") {
      // Legacy positional args: (host, port, token)
      this.baseUrl = `http://${configOrHost}:${port}`;
      this.token = token;
    } else {
      // New config object style
      const host = configOrHost.host ?? "localhost";
      const p = configOrHost.port ?? 9876;
      this.baseUrl = `http://${host}:${p}`;
      this.token = configOrHost.token;
      this.projectId = configOrHost.projectId;
    }
  }

  setToken(token?: string): void {
    this.token = token;
  }

  setProjectId(projectId?: string): void {
    this.projectId = projectId;
  }

  getProjectId(): string | undefined {
    return this.projectId;
  }

  private getHeaders(contentType = false): Record<string, string> {
    const headers: Record<string, string> = {};
    if (contentType) headers["Content-Type"] = "application/json";
    if (this.token) headers["X-Stackpanel-Token"] = this.token;
    if (this.projectId) headers["X-Stackpanel-Project"] = this.projectId;
    return headers;
  }

  /**
   * Generic GET request
   */
  public async get<T>(path: string): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      headers: this.getHeaders(false),
    });

    if (!res.ok) {
      if (res.status === 401) dispatchAuthError();
      throw new Error(`Agent request failed: ${res.statusText}`);
    }

    return res.json();
  }

  /**
   * Compatibility helper to fetch generated files metadata.
   */
  public async getGeneratedFiles(): Promise<GeneratedFilesResponse> {
    const res = await this.get<{
      success: boolean;
      data?: GeneratedFilesResponse;
      error?: string;
    }>("/api/nix/files");
    if (!res.success) {
      throw new Error(res.error ?? "Failed to get generated files");
    }
    return res.data as GeneratedFilesResponse;
  }

  /**
   * Compatibility helper to map Nix data entities.
   */
  public mapEntity<T>(name: string) {
    return this.nix.mapEntity<T>(name);
  }

  /**
   * Generic POST request
   */
  public async post<T>(path: string, body: unknown): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      if (res.status === 401) dispatchAuthError();
      throw new Error(`Agent request failed: ${res.statusText}`);
    }

    return res.json();
  }

  /**
   * Generic DELETE request
   */
  public async delete<T>(path: string): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "DELETE",
      headers: this.getHeaders(false),
    });

    if (!res.ok) {
      if (res.status === 401) dispatchAuthError();
      throw new Error(`Agent request failed: ${res.statusText}`);
    }

    return res.json();
  }

  async health(): Promise<AgentHealth> {
    const res = await fetch(`${this.baseUrl}/health`);
    return res.json();
  }

  async ping(): Promise<AgentHealth | null> {
    try {
      return await this.health();
    } catch {
      return null;
    }
  }

  async exec(request: ExecRequest): Promise<ExecResult> {
    const res = await fetch(`${this.baseUrl}/api/exec`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  async nixEval<T = unknown>(expression: string): Promise<T> {
    const res = await fetch(`${this.baseUrl}/api/nix/eval`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify({ expression }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  async nixGenerate(): Promise<GenerateResult> {
    const res = await fetch(`${this.baseUrl}/api/nix/generate`, {
      method: "POST",
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Regenerate the secrets package (sops config + secrets files).
   * Call this after updating variables to ensure secrets are in sync.
   * Uses nix run to access the script via flake output, works regardless of devshell.
   * Returns null if regeneration fails.
   */
  async regenerateSecrets(): Promise<ExecResult | null> {
    try {
      // Try nix run first (works outside devshell via flake output)
      // The script name has a colon, so we need to quote it in the attribute path
      return await this.exec({
        command: "nix",
        args: ["run", "--impure", '.#scripts."secrets:generate"'],
      });
    } catch (err) {
      // Fall back to direct command (works inside devshell)
      try {
        return await this.exec({ command: "secrets:generate" });
      } catch {
        console.debug("secrets:generate not available:", err);
        return null;
      }
    }
  }

  async readFile(path: string): Promise<FileContent> {
    const res = await fetch(
      `${this.baseUrl}/api/files?path=${encodeURIComponent(path)}`,
      { headers: this.getHeaders(false) },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  async writeFile(path: string, content: string): Promise<void> {
    const res = await fetch(`${this.baseUrl}/api/files`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify({ path, content }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
  }

  async setSecret(request: SetSecretRequest): Promise<SetSecretResult> {
    const res = await fetch(`${this.baseUrl}/api/secrets/set`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Write a secret to a group's SOPS-encrypted YAML file.
   * Secrets are stored in .stackpanel/secrets/groups/<group>.yaml
   */
  async writeAgenixSecret(
    request: AgenixSecretRequest,
  ): Promise<AgenixSecretResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/write`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Read (decrypt) an age-encrypted secret.
   * Requires the user's AGE private key.
   */
  async readAgenixSecret(
    request: AgenixDecryptRequest,
  ): Promise<AgenixDecryptResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/read`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Delete an age-encrypted secret.
   */
  async deleteAgenixSecret(
    id: string,
  ): Promise<{ deleted: boolean; id: string }> {
    const res = await fetch(
      `${this.baseUrl}/api/secrets/delete?id=${encodeURIComponent(id)}`,
      {
        method: "DELETE",
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * List all age-encrypted secrets.
   */
  async listAgenixSecrets(): Promise<{
    secrets: Array<{
      id: string;
      file: string;
      modTime?: number;
      size?: number;
    }>;
  }> {
    const res = await fetch(`${this.baseUrl}/api/secrets/list`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  // ---------------------------------------------------------------------------
  // SOPS secret management (per-environment YAML files)
  // ---------------------------------------------------------------------------

  /**
   * Read (decrypt) all secrets for an environment from the SOPS YAML file.
   * Returns decrypted key-value pairs.
   */
  async readSopsSecrets(environment = "dev"): Promise<SopsSecretsReadResponse> {
    const res = await fetch(
      `${this.baseUrl}/api/sops/read?environment=${encodeURIComponent(environment)}`,
      { headers: this.getHeaders(false) },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Write/update a single key in a SOPS-encrypted environment YAML file.
   */
  async writeSopsSecret(request: {
    environment?: string;
    key: string;
    value: string;
  }): Promise<{ path: string; environment: string; key: string }> {
    const res = await fetch(`${this.baseUrl}/api/sops/write`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Delete a key from a SOPS-encrypted environment YAML file.
   */
  async deleteSopsSecret(environment: string, key: string): Promise<void> {
    const res = await fetch(
      `${this.baseUrl}/api/sops/delete?environment=${encodeURIComponent(environment)}&key=${encodeURIComponent(key)}`,
      {
        method: "DELETE",
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
  }

  /**
   * List all SOPS environments and their secret key names (not values).
   */
  async listSopsSecrets(): Promise<SopsSecretsListResponse> {
    const res = await fetch(`${this.baseUrl}/api/sops/list`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Get the configured age identity (path or key indicator).
   */
  async getAgeIdentity(): Promise<AgeIdentityResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/identity`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data ?? { type: "", value: "", keyPath: "" };
  }

  /**
   * Set the age identity (path or key content).
   * If value starts with AGE-SECRET-KEY- or -----BEGIN, it's treated as key content.
   * Otherwise, it's treated as a file path.
   */
  async setAgeIdentity(value: string): Promise<AgeIdentityResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/identity`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify({ value }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Get the current KMS configuration.
   */
  async getKMSConfig(): Promise<KMSConfigResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/kms`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return (
      data.data ?? { enable: false, keyArn: "", awsProfile: "", source: "" }
    );
  }

  /**
   * Set the KMS configuration.
   */
  async setKMSConfig(config: KMSConfigRequest): Promise<KMSConfigResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/kms`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(config),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  // ==========================================================================
  // Variables Backend
  // ==========================================================================

  /**
   * Get the configured variables backend ("vals" or "chamber").
   */
  async getVariablesBackend(): Promise<{
    backend: "vals" | "chamber";
    chamber?: { servicePrefix: string };
  }> {
    const res = await fetch(`${this.baseUrl}/api/secrets/backend`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    return data ?? { backend: "vals" };
  }

  // Project management methods

  /**
   * Get installed packages from the devenv/stackpanel config
   */
  async getInstalledPackages(
    options: { limit?: number; offset?: number } = {},
  ): Promise<InstalledPackagesResponse> {
    const params = new URLSearchParams();
    if (options.limit !== undefined) params.set("limit", String(options.limit));
    if (options.offset !== undefined)
      params.set("offset", String(options.offset));
    const query = params.toString();
    const res = await fetch(
      `${this.baseUrl}/api/nixpkgs/installed${query ? `?${query}` : ""}`,
      {
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Search nixpkgs packages via the agent API
   */
  async searchNixpkgs(options: {
    query: string;
    channel?: string;
    limit?: number;
    offset?: number;
  }): Promise<{
    packages: NixpkgsPackage[];
    total: number;
    query: string;
    channel: string;
  }> {
    const params = new URLSearchParams();
    params.set("q", options.query);
    if (options.channel) params.set("channel", options.channel);
    if (options.limit !== undefined) params.set("limit", String(options.limit));
    if (options.offset !== undefined)
      params.set("offset", String(options.offset));

    const res = await fetch(
      `${this.baseUrl}/api/nixpkgs/search?${params.toString()}`,
      {
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  async listProjects(): Promise<{
    projects: Project[];
    default_path?: string;
  }> {
    const res = await fetch(`${this.baseUrl}/api/project/list`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    return {
      projects: data.projects ?? [],
      default_path: data.default_path,
    };
  }

  async getCurrentProject(): Promise<ProjectCurrentResponse> {
    const res = await fetch(`${this.baseUrl}/api/project/current`, {
      headers: this.getHeaders(false),
    });
    return res.json();
  }

  async openProject(path: string): Promise<ProjectOpenResponse> {
    const res = await fetch(`${this.baseUrl}/api/project/open`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify({ path }),
    });
    const data = await res.json();
    if (!data.success && data.error) {
      throw new Error(data.message ?? data.error);
    }
    return data;
  }

  async closeProject(): Promise<void> {
    const res = await fetch(`${this.baseUrl}/api/project/close`, {
      method: "POST",
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
  }

  async validateProject(path: string): Promise<ProjectValidateResponse> {
    const res = await fetch(`${this.baseUrl}/api/project/validate`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify({ path }),
    });
    return res.json();
  }

  async removeProject(path: string): Promise<void> {
    const res = await fetch(
      `${this.baseUrl}/api/project/remove?path=${encodeURIComponent(path)}`,
      {
        method: "DELETE",
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
  }

  // Turbo monorepo methods

  /**
   * Execute a turbo query and return the parsed JSON result.
   * @see https://turbo.build/repo/docs/reference/query
   */
  async turboQuery<T = unknown>(query: string): Promise<T> {
    const result = await this.exec({
      command: "turbo",
      args: ["query", query],
    });

    if (result.exit_code !== 0) {
      throw new Error(`turbo query failed: ${result.stderr || result.stdout}`);
    }

    try {
      return JSON.parse(result.stdout) as T;
    } catch {
      throw new Error(`Failed to parse turbo query response: ${result.stdout}`);
    }
  }

  /**
   * Get all package names in the monorepo using turbo query.
   */
  async getPackages(options?: GetPackagesOptions): Promise<string[]> {
    const result = await this.turboQuery<TurboPackageGraphResult>(
      "query { packageGraph { nodes { items { name path tasks { items { name } } } } } }",
    );

    let packages = result.data.packageGraph.nodes.items.map(
      (item) => item.name,
    );

    if (options?.excludeRoot) {
      packages = packages.filter((name) => name !== "//");
    }

    return packages;
  }

  /**
   * Get the full package graph including paths and tasks.
   */
  async getPackageGraph(
    options?: GetPackageGraphOptions,
  ): Promise<TurboPackage[]> {
    const result = await this.turboQuery<TurboPackageGraphResult>(
      "query { packageGraph { nodes { items { name path tasks { items { name } } } } } }",
    );

    let packages = result.data.packageGraph.nodes.items.map((item) => ({
      name: item.name,
      path: item.path,
      tasks: item.tasks.items.map((t) => ({ name: t.name })),
    }));

    if (options?.excludeRoot) {
      packages = packages.filter((pkg) => pkg.name !== "//");
    }

    return packages;
  }

  // SST Infrastructure methods

  /**
   * Get the SST configuration from Nix.
   */
  async getSSTConfig(): Promise<SSTConfig | null> {
    const res = await fetch(`${this.baseUrl}/api/sst/config`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Get the current SST deployment status.
   */
  async getSSTStatus(): Promise<SSTStatus | null> {
    const res = await fetch(`${this.baseUrl}/api/sst/status`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Get the SST stack outputs.
   */
  async getSSTOutputs(): Promise<Record<string, unknown>> {
    const res = await fetch(`${this.baseUrl}/api/sst/outputs`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data ?? {};
  }

  /**
   * Get the deployed SST resources.
   */
  async getSSTResources(): Promise<SSTResource[]> {
    const res = await fetch(`${this.baseUrl}/api/sst/resources`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data ?? [];
  }

  /**
   * Deploy SST infrastructure.
   */
  async deploySSTInfra(stage: string = "dev"): Promise<SSTDeployResponse> {
    const res = await fetch(`${this.baseUrl}/api/sst/deploy`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify({ stage }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Remove SST infrastructure.
   */
  async removeSSTInfra(
    stage: string = "dev",
  ): Promise<{ success: boolean; output: string; error?: string }> {
    const res = await fetch(`${this.baseUrl}/api/sst/remove`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify({ stage }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  // Process-compose methods

  /**
   * Get the list of processes from process-compose.
   * Returns info about process-compose availability and running processes.
   */
  async getProcessComposeProcesses(): Promise<ProcessComposeStatusResponse> {
    const res = await fetch(`${this.baseUrl}/api/process-compose/processes`, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data ?? { available: false, running: false, processes: [] };
  }

  /**
   * Get the project state from process-compose.
   * Includes process counts, memory stats, and version info.
   */
  async getProcessComposeProjectState(): Promise<ProcessComposeProjectState> {
    const res = await fetch(
      `${this.baseUrl}/api/process-compose/project/state`,
      {
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data ?? { available: false };
  }

  /**
   * Get detailed info about a specific process.
   */
  async getProcessInfo(name: string): Promise<Record<string, unknown> | null> {
    const res = await fetch(
      `${this.baseUrl}/api/process-compose/process/info/${encodeURIComponent(name)}`,
      { headers: this.getHeaders(false) },
    );
    const data = await res.json();
    if (!data.success) return null;
    return data.data;
  }

  /**
   * Get ports used by a specific process.
   */
  async getProcessPorts(name: string): Promise<ProcessPorts | null> {
    const res = await fetch(
      `${this.baseUrl}/api/process-compose/process/ports/${encodeURIComponent(name)}`,
      { headers: this.getHeaders(false) },
    );
    const data = await res.json();
    if (!data.success) return null;
    return data.data;
  }

  /**
   * Get logs for a specific process.
   * @param name Process name
   * @param offset Offset from end of log (0 = most recent)
   * @param limit Max number of lines to return
   */
  async getProcessLogs(
    name: string,
    offset = 0,
    limit = 100,
  ): Promise<ProcessLogs> {
    const res = await fetch(
      `${this.baseUrl}/api/process-compose/process/logs/${encodeURIComponent(name)}?offset=${offset}&limit=${limit}`,
      { headers: this.getHeaders(false) },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data ?? { logs: [] };
  }

  /**
   * Start a specific process.
   */
  async startProcess(
    name: string,
  ): Promise<{ success: boolean; message?: string; error?: string }> {
    const res = await fetch(
      `${this.baseUrl}/api/process-compose/process/start/${encodeURIComponent(name)}`,
      {
        method: "POST",
        headers: this.getHeaders(false),
      },
    );
    return res.json();
  }

  /**
   * Stop a specific process.
   */
  async stopProcess(
    name: string,
  ): Promise<{ success: boolean; message?: string; error?: string }> {
    const res = await fetch(
      `${this.baseUrl}/api/process-compose/process/stop/${encodeURIComponent(name)}`,
      {
        method: "POST",
        headers: this.getHeaders(false),
      },
    );
    return res.json();
  }

  /**
   * Restart a specific process.
   */
  async restartProcess(
    name: string,
  ): Promise<{ success: boolean; message?: string; error?: string }> {
    const res = await fetch(
      `${this.baseUrl}/api/process-compose/process/restart/${encodeURIComponent(name)}`,
      {
        method: "POST",
        headers: this.getHeaders(false),
      },
    );
    return res.json();
  }

  /**
   * Create a WebSocket connection to stream process logs.
   * @param name Process name
   * @param follow If true, continue streaming new lines
   * @param offset Offset from end of log
   */
  createProcessLogsWebSocket(
    name: string,
    options: { follow?: boolean; offset?: number } = {},
  ): WebSocket {
    const { follow = true, offset = 0 } = options;
    const wsUrl = this.baseUrl.replace(/^http/, "ws");
    return new WebSocket(
      `${wsUrl}/api/process-compose/logs/ws?name=${encodeURIComponent(name)}&follow=${follow}&offset=${offset}`,
    );
  }

  // ---------------------------------------------------------------------------
  // Group-based secrets management (SOPS files per access control group)
  // ---------------------------------------------------------------------------

  /**
   * Write a secret to a group's SOPS file.
   * Returns the vals reference to use in app configs.
   */
  async writeGroupSecret(
    request: GroupSecretWriteRequest,
  ): Promise<GroupSecretWriteResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/group/write`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Read (decrypt) a secret from a group's SOPS file.
   */
  async readGroupSecret(
    request: GroupSecretReadRequest,
  ): Promise<GroupSecretReadResponse> {
    const res = await fetch(`${this.baseUrl}/api/secrets/group/read`, {
      method: "POST",
      headers: this.getHeaders(true),
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Delete a secret from a group's SOPS file.
   */
  async deleteGroupSecret(
    group: string,
    key: string,
  ): Promise<{ key: string; group: string; deleted: boolean }> {
    const res = await fetch(
      `${this.baseUrl}/api/secrets/group/delete?group=${encodeURIComponent(group)}&key=${encodeURIComponent(key)}`,
      {
        method: "DELETE",
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * List secrets in a group (keys only, not values).
   * If no group specified, lists all groups and their keys.
   */
  async listGroupSecrets(
    group?: string,
  ): Promise<GroupSecretListResponse | AllGroupsListResponse> {
    const url = group
      ? `${this.baseUrl}/api/secrets/group/list?group=${encodeURIComponent(group)}`
      : `${this.baseUrl}/api/secrets/group/list`;
    const res = await fetch(url, {
      headers: this.getHeaders(false),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }

  /**
   * Generate the packages/env data directory.
   * Creates:
   * - apps/<app>/<env>.yaml - Plain YAML with vals references
   * - groups/<group>.yaml - SOPS-encrypted files
   * - .sops.yaml - SOPS configuration
   */
  async generateEnvPackage(): Promise<GenerateEnvPackageResponse> {
    const res = await fetch(
      `${this.baseUrl}/api/secrets/generate-env-package`,
      {
        method: "POST",
        headers: this.getHeaders(false),
      },
    );
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    return data.data;
  }
}

// Default export singleton
export const agent = new AgentHttpClient();

if (typeof window !== "undefined") {
  (window as any)._agent = agent;
  const token = localStorage.getItem("stackpanel.agent.token");
  if (token) {
    (window as any)._agent.setToken(token);
  }
}
