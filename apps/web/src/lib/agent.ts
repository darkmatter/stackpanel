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

type MessageType =
  | "exec"
  | "nix.eval"
  | "nix.generate"
  | "file.read"
  | "file.write"
  | "secrets.set";

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
   */
  async setSecret(request: SetSecretRequest): Promise<SetSecretResult> {
    return this.send<SetSecretResult>("secrets.set", request);
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
  private token?: string;

  constructor(host = "localhost", port = 9876, token?: string) {
    this.baseUrl = `http://${host}:${port}`;
    this.token = token;
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

  // Project management methods

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
}

// Default export singleton
export const agent = new AgentClient();
