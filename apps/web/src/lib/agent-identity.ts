export interface AgentCredential {
  readonly origin: string;
  readonly token: string;
}

/** A hostname is not a URL. Never let userinfo, a path, or a second port change its authority. */
export function canonicalAgentOrigin(host: string, port: number): string {
  if (
    !Number.isInteger(port) ||
    port < 1 ||
    port > 65535 ||
    !/^(?:[a-z\d.-]+|\[[a-f\d:.]+\])$/i.test(host)
  ) {
    throw new Error("Invalid agent host or port");
  }
  return new URL(`http://${host}:${port}`).origin;
}

export function agentTokenKey(origin: string): string {
  return `stackpanel.agent.token:${origin}`;
}

// This is a routing check, not signature verification. Only the matching agent
// receives the token and decides whether its signature and origin are valid.
export function tokenAgentId(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3 || !parts.every((part) => /^[\w-]+$/.test(part))) return null;
    const claims = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return typeof claims.agent_id === "string" &&
      claims.agent_id.trim() &&
      Number.isFinite(claims.exp) &&
      claims.exp > Date.now() / 1000
      ? claims.agent_id
      : null;
  } catch {
    return null;
  }
}

export interface PublicAgentHealth {
  agentId: string | null;
  projectRoot: string | null;
}

export async function readPublicAgentHealth(
  origin: string,
  signal?: AbortSignal,
): Promise<PublicAgentHealth> {
  const response = await fetch(`${origin}/health`, {
    signal,
    credentials: "omit",
    redirect: "error",
    cache: "no-store",
    referrerPolicy: "no-referrer",
  });
  if (!response.ok) throw new Error("Agent unavailable");
  const data = await response.json();
  if (data?.status !== "ok") throw new Error("Invalid agent health response");
  // The browser demo exposes the camel-case equivalent of the agent's wire format.
  const id = data.agent_id ?? data.agentId;
  const root = data.project_root ?? data.projectRoot;
  return {
    agentId: typeof id === "string" && id.length > 0 ? id : null,
    projectRoot: typeof root === "string" && root.length > 0 ? root : null,
  };
}

export async function checkAgentIdentity(origin: string, token: string, signal?: AbortSignal) {
  const expected = tokenAgentId(token);
  if (!expected || (await readPublicAgentHealth(origin, signal)).agentId !== expected) {
    throw new Error("Agent identity changed or the pairing expired. Pair again.");
  }
}

/** Probe immediately before sending a credential: a dev agent can be replaced on the same port. */
export async function fetchWithAgentIdentity(
  origin: string,
  token: string,
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const request = typeof input === "object" && "url" in input ? input : undefined;
  const url = new URL(request?.url ?? String(input));
  if (url.origin !== new URL(origin).origin || url.username || url.password) {
    throw new Error("Credential is not scoped to this endpoint");
  }
  const signal = init?.signal ?? request?.signal;
  await checkAgentIdentity(url.origin, token, signal);
  signal?.throwIfAborted();
  return fetch(input, {
    ...init,
    redirect: "error",
    credentials: "omit",
    referrerPolicy: "no-referrer",
  });
}
