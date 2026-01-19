import { useCallback, useEffect, useState, useMemo } from "react";
import {
	type AgentHealth,
	AgentHttpClient,
	type ExecResult,
	type FileContent,
	type GenerateResult,
	type SetSecretResult,
} from "./agent";

interface UseAgentOptions {
	host?: string;
	port?: number;
	token?: string;
}

interface UseAgentReturn {
	isConnected: boolean;
	isConnecting: boolean;
	error: Error | null;
	connect: () => Promise<void>;
	disconnect: () => void;
	exec: (command: string, args?: string[]) => Promise<ExecResult>;
	nixEval: <T = unknown>(expression: string) => Promise<T>;
	nixGenerate: () => Promise<GenerateResult>;
	readFile: (path: string) => Promise<FileContent>;
	writeFile: (path: string, content: string) => Promise<void>;
	setSecret: (
		env: "dev" | "staging" | "prod",
		key: string,
		value: string,
	) => Promise<SetSecretResult>;
}

/**
 * React hook for interacting with the StackPanel agent.
 * Now uses AgentHttpClient (HTTP) instead of AgentClient (WebSocket).
 */
export function useAgent(options: UseAgentOptions = {}): UseAgentReturn {
	const {
		host = "localhost",
		port = 9876,
		token,
	} = options;

	const client = useMemo(() => new AgentHttpClient({ host, port, token }), [host, port, token]);

	const { status } = useAgentHealth({ host, port });
	const isConnected = status === "available";

	return {
		isConnected,
		isConnecting: status === "checking",
		error: null,
		connect: async () => {}, // No-op for HTTP
		disconnect: () => {},    // No-op for HTTP
		exec: (command, args) => client.exec({ command, args }),
		nixEval: (expression) => client.nixEval(expression),
		nixGenerate: () => client.nixGenerate(),
		readFile: (path) => client.readFile(path),
		writeFile: (path, content) => client.writeFile(path, content),
		setSecret: (env, key, value) => client.setSecret({ env, key, value }),
	};
}

/**
 * Hook for checking if agent is available (health check)
 */
export function useAgentHealth(
	options: { host?: string; port?: number; intervalMs?: number } = {},
) {
	const { host = "localhost", port = 9876, intervalMs = 15e3 } = options;

	const [status, setStatus] = useState<
		"checking" | "available" | "unavailable"
	>("checking");
	const [projectRoot, setProjectRoot] = useState<string | null>(null);
	const [hasProject, setHasProject] = useState<boolean>(false);
	const [agentId, setAgentId] = useState<string | null>(null);

	useEffect(() => {
		const client = new AgentHttpClient(host, port);
		let isMounted = true;

		const check = () => {
			client.ping().then((data) => {
				if (!isMounted) return;
				if (data) {
					setStatus("available");
					setProjectRoot(data.project_root ?? null);
					setHasProject(data.has_project ?? !!data.project_root);
					setAgentId((data as { agent_id?: string }).agent_id ?? null);
				} else {
					setStatus("unavailable");
					setProjectRoot(null);
					setHasProject(false);
					setAgentId(null);
				}
			});
		};

		check();
		const interval = setInterval(check, intervalMs);

		return () => {
			isMounted = false;
			clearInterval(interval);
		};
	}, [host, port, intervalMs]);

	return { status, projectRoot, hasProject, agentId };
}
