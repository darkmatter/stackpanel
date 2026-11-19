const routeId = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/;
const ipv4Loopback = /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
const ticket = /^[A-Za-z0-9_-]{32,2048}$/;
const portOf = (url: URL) => url.port || (url.protocol === "https:" ? "443" : "80");

function assetSegment(part: string): boolean {
  const name = decodeURIComponent(part);
  return name !== "" && name !== "." && name !== ".." && !/[\\/%?#\p{Cc}]/u.test(name);
}

/** Use the same loopback validation for diagnostics as for a launch, but
 * never render the path, query or credentials from a machine-local link. */
export function localDevUrl(raw: string): URL | null {
  if (!/^https?:\/\//.test(raw) || /[\\?#@\s]/.test(raw)) return null;
  try {
    const url = new URL(raw);
    if (
      url.username ||
      url.password ||
      !(url.hostname === "localhost" || url.hostname === "[::1]" || ipv4Loopback.test(url.hostname))
    )
      return null;
    return url;
  } catch {
    return null;
  }
}

/** Validate before URL parsing: a browser would silently normalize dot segments. */
export function extensionFrameUrl(
  agentOrigin: string,
  studioOrigin: string,
  moduleId: string,
  panelId: string,
  response: { url: string; devUrl: string },
): URL {
  if (!routeId.test(moduleId) || !routeId.test(panelId)) throw new Error("Invalid extension ID");
  if (response.devUrl) {
    const url = localDevUrl(response.devUrl);
    if (!url || portOf(url) === portOf(new URL(agentOrigin)) || url.origin === studioOrigin) {
      throw new Error("The extension development URL must refer to a separate loopback server");
    }
    return url;
  }
  const prefix = `/api/v1/modules/${moduleId}/ui/${panelId}/_ticket/`;
  if (!response.url.startsWith(prefix)) throw new Error("Unscoped extension asset URL");
  const [id, ...entry] = response.url.slice(prefix.length).split("/");
  if (!id || !ticket.test(id) || !entry.length || !entry.every(assetSegment)) {
    throw new Error("Invalid extension asset ticket or entry");
  }
  return new URL(response.url, agentOrigin);
}

export function bridgeNonce(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(16)), (n) =>
    n.toString(16).padStart(2, "0"),
  ).join("");
}
