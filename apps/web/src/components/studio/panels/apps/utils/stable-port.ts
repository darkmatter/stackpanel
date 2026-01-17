/**
 * Compute stable port from project name and service name.
 * Mirrors the Nix stablePort function from ports.nix
 */
export function computeStablePort(repo: string, service: string): number {
  const MIN_PORT = 3000;
  const MAX_PORT = 10000;
  const MODULUS = 100;

  // Simple hash function using string char codes
  const hashString = (s: string): number => {
    let hash = 0;
    for (let i = 0; i < s.length; i++) {
      const char = s.charCodeAt(i);
      hash = (hash << 5) - hash + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash);
  };

  // Compute project base port
  const range = MAX_PORT - MIN_PORT;
  const repoHash = hashString(repo);
  const offset = repoHash % range;
  const roundedOffset = offset - (offset % MODULUS);
  const projectBase = MIN_PORT + roundedOffset;

  // Compute service port within the project range
  const serviceHash = hashString(service);
  const serviceOffset = serviceHash % MODULUS;
  const servicePort = projectBase + serviceOffset;

  return servicePort;
}
