/**
 * Hook + helpers for revealing a single SOPS-encrypted secret on demand.
 *
 * The Studio UI carries a `sops` reference of the form "/<group>/<key>" on
 * each secret env entry (e.g. "/dev/postgres-url"). Resolving that to a value
 * is intentionally a thin wrapper around the canonical CLI workflow:
 *
 *   sops decrypt --extract '["<key>"]' <projectSecretsDir>/vars/<group>.sops.yaml
 *
 * The reveal is invoked through the agent's `Exec` RPC so the agent process
 * (which already has `sops` and the configured AGE identity on PATH) does the
 * decryption — the browser never sees the master key, only the resolved value.
 */
import { useCallback, useState } from "react";
import { useAgentRpcClient, useProject } from "@/lib/use-agent";

export interface ParsedSopsRef {
	group: string;
	key: string;
}

/**
 * Parse a "/<group>/<key>" sops reference. Returns null when the input does
 * not match (so callers can hide the toggle gracefully instead of crashing).
 */
export function parseSopsRef(ref: string | undefined): ParsedSopsRef | null {
	if (!ref) return null;
	const parts = ref
		.trim()
		.replace(/^\/+/, "")
		.split("/")
		.filter(Boolean);
	if (parts.length < 2) return null;
	const key = parts[parts.length - 1];
	const group = parts.slice(0, -1).join("/");
	if (!group || !key) return null;
	return { group, key };
}

/**
 * Build the absolute group-file path that `sops` will operate on.
 * Mirrors the canonical layout described in `nix/stackpanel/secrets/lib.nix`:
 *   <projectSecretsDir>/vars/<group>.sops.yaml
 */
export function buildSopsFilePath(
	projectSecretsDir: string,
	group: string,
): string {
	const trimmed = projectSecretsDir.replace(/\/+$/, "");
	return `${trimmed}/vars/${group}.sops.yaml`;
}

interface RevealState {
	envKey: string | null;
	value: string | null;
	error: string | null;
	loading: boolean;
}

const initialState: RevealState = {
	envKey: null,
	value: null,
	error: null,
	loading: false,
};

/**
 * Tracks the currently revealed secret (one at a time) and exposes a
 * `reveal(envKey, sopsRef)` action that decrypts via the agent.
 *
 * Only one secret may be revealed at a time — calling `reveal` for a different
 * envKey transparently replaces the previous one. Calling it with the same
 * envKey again hides the value (toggle behaviour).
 */
export function useRevealSecret() {
	const client = useAgentRpcClient();
	const { data: project } = useProject();
	const [state, setState] = useState<RevealState>(initialState);

	const hide = useCallback(() => setState(initialState), []);

	const reveal = useCallback(
		async (envKey: string, sopsRef: string | undefined) => {
			if (state.envKey === envKey) {
				hide();
				return;
			}

			const parsed = parseSopsRef(sopsRef);
			const secretsDir = project?.dirs?.secrets;

			if (!parsed) {
				setState({
					envKey,
					value: null,
					error: "Missing or malformed sops reference",
					loading: false,
				});
				return;
			}
			if (!secretsDir) {
				setState({
					envKey,
					value: null,
					error: "Project secrets directory not yet available",
					loading: false,
				});
				return;
			}
			if (!client) {
				setState({
					envKey,
					value: null,
					error: "Not connected to agent",
					loading: false,
				});
				return;
			}

			setState({ envKey, value: null, error: null, loading: true });

			const filePath = buildSopsFilePath(secretsDir, parsed.group);
			try {
				const res = await client.exec({
					command: "sops",
					args: [
						"decrypt",
						"--extract",
						`["${parsed.key}"]`,
						filePath,
					],
				});

				if (res.exitCode !== 0) {
					const stderr = res.stderr?.trim();
					setState({
						envKey,
						value: null,
						error:
							stderr && stderr.length > 0
								? stderr
								: `sops exited with code ${res.exitCode}`,
						loading: false,
					});
					return;
				}

				setState({
					envKey,
					value: res.stdout?.replace(/\n+$/, "") ?? "",
					error: null,
					loading: false,
				});
			} catch (err) {
				setState({
					envKey,
					value: null,
					error: err instanceof Error ? err.message : String(err),
					loading: false,
				});
			}
		},
		[client, hide, project?.dirs?.secrets, state.envKey],
	);

	return {
		revealedEnvKey: state.envKey,
		revealedValue: state.value,
		revealError: state.error,
		isRevealing: state.loading,
		reveal,
		hide,
	};
}
