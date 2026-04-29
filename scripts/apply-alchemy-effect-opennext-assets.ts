#!/usr/bin/env bun
/**
 * Copies vendored `alchemy-effect@0.12.x` Cloudflare Worker asset overlay patches
 * into every `node_modules/alchemy-effect` tree after `bun install`.
 *
 * Replaces `patchedDependencies` (Bun patch format was unreliable for this repo layout).
 */
import { copyFileSync, readFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const vendorDir = join(root, "vendor", "alchemy-effect-opennext-overlay");
const srcAssets = join(vendorDir, "Assets.ts");
const srcWorker = join(vendorDir, "Worker.ts");

if (!existsSync(srcAssets) || !existsSync(srcWorker)) {
  console.warn(
    "[apply-alchemy-effect-opennext-assets] vendor files missing; skip",
  );
  process.exit(0);
}

// Vendored sources are derived from alchemy-effect@0.12.x. Refuse to overwrite
// any other minor — a transitive bump to 0.13+ should fail loudly so we
// re-vendor instead of silently shipping stale overlays.
const SUPPORTED_RANGE = /^0\.12\./;
const skipped: { pkgRoot: string; version: string }[] = [];

function patchInstallAt(pkgRoot: string, seen: Set<string>, n: { v: number }) {
  if (seen.has(pkgRoot)) return;
  const pkgPath = join(pkgRoot, "package.json");
  if (!existsSync(pkgPath)) return;
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as {
    name?: string;
    version?: string;
  };
  if (pkg.name !== "alchemy-effect") return;
  const destAssets = join(pkgRoot, "src", "Cloudflare", "Workers", "Assets.ts");
  const destWorker = join(pkgRoot, "src", "Cloudflare", "Workers", "Worker.ts");
  if (!existsSync(dirname(destAssets))) return;
  seen.add(pkgRoot);
  if (!pkg.version || !SUPPORTED_RANGE.test(pkg.version)) {
    skipped.push({ pkgRoot, version: pkg.version ?? "<unknown>" });
    return;
  }
  copyFileSync(srcAssets, destAssets);
  copyFileSync(srcWorker, destWorker);
  n.v++;
}

const seen = new Set<string>();
const n = { v: 0 };

/** Bun stores duplicated packages under `node_modules/.bun/<name>@<version>+.../`. */
function scanBunStore(bunRoot: string) {
  if (!existsSync(bunRoot)) return;
  for (const entry of readdirSync(bunRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith("alchemy-effect@")) {
      continue;
    }
    const pkgRoot = join(bunRoot, entry.name, "node_modules", "alchemy-effect");
    patchInstallAt(pkgRoot, seen, n);
  }
}

scanBunStore(join(root, "node_modules", ".bun"));
const appsDir = join(root, "apps");
if (existsSync(appsDir)) {
  for (const app of readdirSync(appsDir, { withFileTypes: true })) {
    if (!app.isDirectory()) continue;
    scanBunStore(join(appsDir, app.name, "node_modules", ".bun"));
  }
}

const glob = new Bun.Glob("**/node_modules/alchemy-effect/package.json");
for await (const rel of glob.scan({ cwd: root, onlyFiles: true })) {
  const pkgRoot = join(root, dirname(rel));
  patchInstallAt(pkgRoot, seen, n);
}

if (skipped.length > 0) {
  console.error(
    `[apply-alchemy-effect-opennext-assets] refusing to patch ${skipped.length} alchemy-effect install(s) outside the vendored 0.12.x range:`,
  );
  for (const s of skipped) {
    console.error(`  - ${s.version}  (${s.pkgRoot})`);
  }
  console.error(
    "  Re-vendor vendor/alchemy-effect-opennext-overlay/{Assets,Worker}.ts from the new version, or pin alchemy-effect back to 0.12.x.",
  );
  process.exit(1);
}

if (n.v === 0) {
  console.error(
    "[apply-alchemy-effect-opennext-assets] no alchemy-effect@0.12.x installs found — overlay is not applied. " +
      "Either alchemy-effect is no longer a dependency (delete this hook), or it resolved to an unsupported version.",
  );
  process.exit(1);
}

console.log(
  `[apply-alchemy-effect-opennext-assets] patched ${n.v} alchemy-effect install(s)`,
);
