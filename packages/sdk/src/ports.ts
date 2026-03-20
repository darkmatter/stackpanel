import { subtle } from "crypto";

const MODULO = 100;
const MIN = 3000;
const MAX = 10000;

/**
 * Implements stackpanel deterministic port resolution.
 */
export async function stablePort(options: StablePortOptions): Promise<number> {
  const prange = await cor(options.repo, MIN, MAX, MODULO);
  const srange = await cor(options.serviceName, prange, MAX, MODULO);
  return srange;
}

async function cor(key: string, min: number, max: number, modulo: number) {
  const h = await hashnum(key);
  const num = parseInt(h, 16);
  const rawOffset = num % (max - min);
  const roundedOffset = Math.floor(rawOffset / modulo) * modulo;
  return min + roundedOffset;
}

export async function hashnum(ref: string): Promise<string> {
  return subtle.digest("SHA-256", new TextEncoder().encode(ref)).then((h) => {
    const bytes = new Uint8Array(h);
    // get int value of first 2 bytes
    const port = (bytes[0] << 8) | bytes[1];
    return port.toString();
  });
}

interface StablePortOptions {
  serviceName: string;
  repo: string;
}
