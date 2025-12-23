/**
 * StackPanel Agent Client
 *
 * Connects to the local agent running on the developer's machine
 * to execute commands and manage files.
 */

export interface AgentConfig {
	host?: string;
	port?: number;
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

type MessageType =
	| "exec"
	| "nix.eval"
	| "nix.generate"
	| "file.read"
	| "file.write";

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
	private config: Required<AgentConfig>;
	private pendingRequests = new Map<string, PendingRequest<unknown>>();
	private messageId = 0;
	private reconnectAttempts = 0;
	private maxReconnectAttempts = 5;
	private reconnectDelay = 1000;

	constructor(config: AgentConfig = {}) {
		this.config = {
			host: config.host ?? "localhost",
			port: config.port ?? 9876,
			onConnect: config.onConnect ?? (() => {}),
			onDisconnect: config.onDisconnect ?? (() => {}),
			onError: config.onError ?? (() => {}),
		};
	}

	/**
	 * Connect to the agent
	 */
	connect(): Promise<void> {
		return new Promise((resolve, reject) => {
			const url = `ws://${this.config.host}:${this.config.port}/ws`;

			try {
				this.ws = new WebSocket(url);
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

			this.ws.onerror = (event) => {
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
export class AgentHttpClient {
	private baseUrl: string;

	constructor(host = "localhost", port = 9876) {
		this.baseUrl = `http://${host}:${port}`;
	}

	async health(): Promise<{ status: string; project_root: string }> {
		const res = await fetch(`${this.baseUrl}/health`);
		return res.json();
	}

	async exec(request: ExecRequest): Promise<ExecResult> {
		const res = await fetch(`${this.baseUrl}/api/exec`, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(request),
		});
		const data = await res.json();
		if (!data.success) throw new Error(data.error);
		return data.data;
	}

	async nixEval<T = unknown>(expression: string): Promise<T> {
		const res = await fetch(`${this.baseUrl}/api/nix/eval`, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ expression }),
		});
		const data = await res.json();
		if (!data.success) throw new Error(data.error);
		return data.data;
	}

	async nixGenerate(): Promise<GenerateResult> {
		const res = await fetch(`${this.baseUrl}/api/nix/generate`, {
			method: "POST",
		});
		const data = await res.json();
		if (!data.success) throw new Error(data.error);
		return data.data;
	}

	async readFile(path: string): Promise<FileContent> {
		const res = await fetch(
			`${this.baseUrl}/api/files?path=${encodeURIComponent(path)}`,
		);
		const data = await res.json();
		if (!data.success) throw new Error(data.error);
		return data.data;
	}

	async writeFile(path: string, content: string): Promise<void> {
		const res = await fetch(`${this.baseUrl}/api/files`, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ path, content }),
		});
		const data = await res.json();
		if (!data.success) throw new Error(data.error);
	}
}

// Default export singleton
export const agent = new AgentClient();
