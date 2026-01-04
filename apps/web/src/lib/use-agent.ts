import { useCallback, useEffect, useState } from "react";
import {
	AgentClient,
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
	autoConnect?: boolean;
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
 * React hook for interacting with the StackPanel agent
 */
export function useAgent(options: UseAgentOptions = {}): UseAgentReturn {
	const {
		host = "localhost",
		port = 9876,
		token,
		autoConnect = true,
	} = options;

	const [client] = useState(() => new AgentClient({ host, port, token }));
	const [isConnected, setIsConnected] = useState(false);
	const [isConnecting, setIsConnecting] = useState(false);
	const [error, setError] = useState<Error | null>(null);

	// Keep token up to date (needed after pairing).
	useEffect(() => {
		client.setToken(token);
	}, [client, token]);

	const connect = useCallback(async () => {
		setIsConnecting(true);
		setError(null);

		try {
			if (!token) {
				throw new Error("Missing agent token (pair first)");
			}
			await client.connect();
			setIsConnected(true);
		} catch (err) {
			setError(err instanceof Error ? err : new Error("Connection failed"));
			setIsConnected(false);
		} finally {
			setIsConnecting(false);
		}
	}, [client, token]);

	const disconnect = useCallback(() => {
		client.disconnect();
		setIsConnected(false);
	}, [client]);

	// Setup event handlers
	useEffect(() => {
		const originalConfig = {
			onConnect: () => setIsConnected(true),
			onDisconnect: () => setIsConnected(false),
			onError: (err: Error) => setError(err),
		};

		// Update client config
		Object.assign(client, {
			config: { ...client["config"], ...originalConfig },
		});

		if (autoConnect && token) {
			connect();
		}

		return () => {
			client.disconnect();
		};
	}, [client, autoConnect, connect, token]);

	return {
		isConnected,
		isConnecting,
		error,
		connect,
		disconnect,
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
	const { host = "localhost", port = 9876, intervalMs = 2000 } = options;

	const [status, setStatus] = useState<
		"checking" | "available" | "unavailable"
	>("checking");
	const [projectRoot, setProjectRoot] = useState<string | null>(null);

	useEffect(() => {
		const client = new AgentHttpClient(host, port);
		let isMounted = true;

		const check = () => {
			client.ping().then((data) => {
				if (!isMounted) return;
				if (data) {
					setStatus("available");
					setProjectRoot(data.project_root);
				} else {
					setStatus("unavailable");
					setProjectRoot(null);
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

	return { status, projectRoot };
}
