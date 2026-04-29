Vendored copies of `alchemy-effect@0.12.x`:

- `Assets.ts` → `src/Cloudflare/Workers/Assets.ts`
- `Worker.ts` → `src/Cloudflare/Workers/Worker.ts`

After `bun install`, `scripts/apply-alchemy-effect-opennext-assets.ts` (root `postinstall`) copies these into every `alchemy-effect` install (including `node_modules/.bun/alchemy-effect@*/…`).

Upstream: same change lives in `alchemy-effect` / `alchemy` (`feat`: asset `sources` overlays). Remove this vendor hook once a published `alchemy-effect` release includes it.
