/**
 * StackPanel Agent Client
 *
 * Connects to the local agent running on the developer's machine
 * to execute commands and manage files.
 */

export interface Project {
	path: string;
	name: string;
	last_opened: string;
	active: boolean;
}

export interface ProjectListResponse {
	projects: Project[];
}

export interface ProjectCurrentResponse {
	has_project: boolean;
	project: Project | null;
}

export interface ProjectOpenResponse {
	success: boolean;
	project: Project;
	devshell?: {
		in_devshell: boolean;
		has_devshell_env: boolean;
		error?: string;
	};
}

export interface ProjectValidateResponse {
	valid: boolean;
	error?: string;
	message?: string;
}

export interface AgentConfig {
	host?: string;
	port?: number;
	token?: string;
	onConnect?: () => void;
	onDisconnect?: () => void;
	onError?: (error: Error) => void;
}

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

export interface NixEvalRequest {
	expression: string;
	file?: string;
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

export interface AgentHealth {
	status: string;
	project_root?: string;
	has_project?: boolean;
	agent_id?: string;
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

/** @deprecated Use TurboPackageGraphResult instead */
export interface TurboPackagesQueryResult {
	data: {
		packages: {
			items: Array<{ name: string }>;
		};
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

type MessageType =
	| "exec"
	| "nix.eval"
	| "nix.generate"
	| "file.read"
	| "file.write"
	| "secrets.set"
	| "secrets.write"
	| "secrets.read"
	| "secrets.delete"
	| "secrets.list";

interface Message {
	id: string;
	type: MessageType;
	payload: unknown;
}

interface Response<T = unknown> {
	id: string;
	success: boolean;
	data?: T;
	error?: string;
}

type PendingRequest<T> = {
	resolve: (value: T) => void;
	reject: (error: Error) => void;
};

export class AgentClient {
	private ws: WebSocket | null = null;
	private config: {
		host: string;
		port: number;
		token?: string;
		onConnect: () => void;
		onDisconnect: () => void;
		onError: (error: Error) => void;
	};
	private pendingRequests = new Map<string, PendingRequest<unknown>>();
	private messageId = 0;
	private reconnectAttempts = 0;
	private maxReconnectAttempts = 5;
	private reconnectDelay = 1000;

	constructor(config: AgentConfig = {}) {
		this.config = {
			host: config.host ?? "localhost",
			port: config.port ?? 9876,
			token: config.token,
			onConnect: config.onConnect ?? (() => {}),
			onDisconnect: config.onDisconnect ?? (() => {}),
			onError: config.onError ?? (() => {}),
		};
	}

	setToken(token?: string): void {
		this.config.token = token;
	}

	/**
	 * Connect to the agent
	 */
	connect(): Promise<void> {
		return new Promise((resolve, reject) => {
			const u = new URL(`ws://${this.config.host}:${this.config.port}/ws`);
			if (this.config.token) {
				u.searchParams.set("token", this.config.token);
			}

			try {
				this.ws = new WebSocket(u.toString());
			} catch (err) {
				reject(new Error(`Failed to create WebSocket: ${err}`));
				return;
			}

			this.ws.onopen = () => {
				this.reconnectAttempts = 0;
				this.config.onConnect();
				resolve();
			};

			this.ws.onclose = () => {
				this.config.onDisconnect();
				this.attemptReconnect();
			};

			this.ws.onerror = (_event) => {
				const error = new Error("WebSocket error");
				this.config.onError(error);
				reject(error);
			};

			this.ws.onmessage = (event) => {
				this.handleMessage(event.data);
			};
		});
	}

	/**
	 * Ping the agent over HTTP to see if it's available.
	 */
	async ping(): Promise<AgentHealth | null> {
		try {
			const res = await fetch(
				`http://${this.config.host}:${this.config.port}/health`,
			);
			if (!res.ok) return null;
			return (await res.json()) as AgentHealth;
		} catch {
			return null;
		}
	}

	/**
	 * Disconnect from the agent
	 */
	disconnect(): void {
		if (this.ws) {
			this.ws.close();
			this.ws = null;
		}
	}

	/**
	 * Check if connected
	 */
	get isConnected(): boolean {
		return this.ws?.readyState === WebSocket.OPEN;
	}

	/**
	 * Execute a command
	 */
	async exec(request: ExecRequest): Promise<ExecResult> {
		return this.send<ExecResult>("exec", request);
	}

	/**
	 * Evaluate a Nix expression
	 */
	async nixEval<T = unknown>(expression: string): Promise<T> {
		return this.send<T>("nix.eval", { expression });
	}

	/**
	 * Run nix generate
	 */
	async nixGenerate(): Promise<GenerateResult> {
		return this.send<GenerateResult>("nix.generate", {});
	}

	/**
	 * Read a file
	 */
	async readFile(path: string): Promise<FileContent> {
		return this.send<FileContent>("file.read", { path });
	}

	/**
	 * Write a file
	 */
	async writeFile(path: string, content: string): Promise<void> {
		await this.send("file.write", { path, content });
	}

	/**
	 * Set a secret in .stackpanel/secrets/<env>.yaml (encrypted via sops + team recipients).
	 * @deprecated Use writeAgenixSecret for age-encrypted secrets
	 */
	async setSecret(request: SetSecretRequest): Promise<SetSecretResult> {
		return this.send<SetSecretResult>("secrets.set", request);
	}

	/**
	 * Write an age-encrypted secret using agenix.
	 * Creates a .age file in .stackpanel/secrets/vars/<id>.age
	 * and updates variables.nix with secret metadata.
	 */
	async writeAgenixSecret(request: AgenixSecretRequest): Promise<AgenixSecretResponse> {
		return this.send<AgenixSecretResponse>("secrets.write", request);
	}

	/**
	 * Read (decrypt) an age-encrypted secret.
	 * Requires the user's AGE private key.
	 */
	async readAgenixSecret(request: AgenixDecryptRequest): Promise<AgenixDecryptResponse> {
		return this.send<AgenixDecryptResponse>("secrets.read", request);
	}

	/**
	 * Delete an age-encrypted secret.
	 * Removes the .age file and updates variables.nix.
	 */
	async deleteAgenixSecret(id: string): Promise<{ deleted: boolean; id: string }> {
		return this.send<{ deleted: boolean; id: string }>("secrets.delete", { id });
	}

	/**
	 * List all age-encrypted secrets.
	 */
	async listAgenixSecrets(): Promise<{ secrets: Array<{ id: string; file: string; modTime?: number; size?: number }> }> {
		return this.send<{ secrets: Array<{ id: string; file: string; modTime?: number; size?: number }> }>("secrets.list", {});
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

	// Private methods

	private send<T>(type: MessageType, payload: unknown): Promise<T> {
		return new Promise((resolve, reject) => {
			if (!this.isConnected) {
				reject(new Error("Not connected to agent"));
				return;
			}

			const id = String(++this.messageId);
			const message: Message = { id, type, payload };

			this.pendingRequests.set(id, {
				resolve: resolve as (value: unknown) => void,
				reject,
			});

			this.ws!.send(JSON.stringify(message));

			// Timeout after 30 seconds
			setTimeout(() => {
				if (this.pendingRequests.has(id)) {
					this.pendingRequests.delete(id);
					reject(new Error("Request timeout"));
				}
			}, 30_000);
		});
	}

	private handleMessage(data: string): void {
		try {
			const response: Response = JSON.parse(data);
			const pending = this.pendingRequests.get(response.id);

			if (pending) {
				this.pendingRequests.delete(response.id);

				if (response.success) {
					pending.resolve(response.data);
				} else {
					pending.reject(new Error(response.error ?? "Unknown error"));
				}
			}
		} catch (err) {
			console.error("Failed to parse agent response:", err);
		}
	}

	private attemptReconnect(): void {
		if (this.reconnectAttempts >= this.maxReconnectAttempts) {
			console.error("Max reconnection attempts reached");
			return;
		}

		this.reconnectAttempts++;
		const delay = this.reconnectDelay * 2 ** (this.reconnectAttempts - 1);

		console.log(
			`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`,
		);

		setTimeout(() => {
			this.connect().catch(() => {
				// Will trigger another reconnect via onclose
			});
		}, delay);
	}
}

/**
 * HTTP client fallback when WebSocket is not available
 */
export interface AgentHttpClientConfig {
	host?: string;
	port?: number;
	token?: string;
}

export class AgentHttpClient {
	private baseUrl: string;
	private token?: string;

	/**
	 * Create an AgentHttpClient.
	 * @param configOrHost - Either a config object { host?, port?, token? } or host string
	 * @param port - Port number (only used if first arg is a string)
	 * @param token - Auth token (only used if first arg is a string)
	 */
	constructor(configOrHost: AgentHttpClientConfig | string = {}, port = 9876, token?: string) {
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
		}
	}

	setToken(token?: string): void {
		this.token = token;
	}

	private getHeaders(contentType = false): Record<string, string> {
		const headers: Record<string, string> = {};
		if (contentType) headers["Content-Type"] = "application/json";
		if (this.token) headers["X-Stackpanel-Token"] = this.token;
		return headers;
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
	 * Write an age-encrypted secret using agenix.
	 * Creates a .age file in .stackpanel/secrets/vars/<id>.age
	 */
	async writeAgenixSecret(request: AgenixSecretRequest): Promise<AgenixSecretResponse> {
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
	async readAgenixSecret(request: AgenixDecryptRequest): Promise<AgenixDecryptResponse> {
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
	async deleteAgenixSecret(id: string): Promise<{ deleted: boolean; id: string }> {
		const res = await fetch(`${this.baseUrl}/api/secrets/delete?id=${encodeURIComponent(id)}`, {
			method: "DELETE",
			headers: this.getHeaders(false),
		});
		const data = await res.json();
		if (!data.success) throw new Error(data.error);
		return data.data;
	}

	/**
	 * List all age-encrypted secrets.
	 */
	async listAgenixSecrets(): Promise<{ secrets: Array<{ id: string; file: string; modTime?: number; size?: number }> }> {
		const res = await fetch(`${this.baseUrl}/api/secrets/list`, {
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
		return data.data ?? { enable: false, keyArn: "", awsProfile: "", source: "" };
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

	async listProjects(): Promise<Project[]> {
		const res = await fetch(`${this.baseUrl}/api/project/list`, {
			headers: this.getHeaders(false),
		});
		const data = await res.json();
		return data.projects ?? [];
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
}

// Default export singleton
export const agent = new AgentClient();

if (typeof window !== "undefined") {
	(window as any)._agent = agent;
	const token = localStorage.getItem("stackpanel.agent.token");
	if (token) {
		(window as any)._agent.setToken(token);
	}
}
