# Upstream PR checklist (`alchemy-effect`)

## Change summary

- **API:** `AssetsProps.sources?: { directory: string; prefix: string }[]` (+ optional `sources` on `AssetsWithHash` in Worker).
- **Behavior:** `read` / `readAssets` merges overlay trees into the Worker asset manifest; `upload` resolves each manifest path via `filePaths` (absolute source paths). Content hash excludes `filePaths` (machine-local paths).
- **Tests:** `packages/alchemy/test/Cloudflare/Workers/Assets.test.ts`
- **Example doc:** `examples/opennext-cloudflare-asset-overlay/README.md`

## Stackpanel validation

- `apps/docs/alchemy.run.ts` passes `sources: [{ directory: ".open-next/cache", prefix: "cdn-cgi/_next_cache" }]`.
- `bun run build:worker` in `apps/docs` (OpenNext) succeeds until `.open-next/worker.js` + `.open-next/cache` exist.
- Until npm ships the change, Stackpanel uses **vendored** `vendor/alchemy-effect-opennext-overlay/*.ts` + `postinstall` (`scripts/apply-alchemy-effect-opennext-assets.ts`).

## Suggested PR title

`feat(cloudflare): overlay asset sources for Worker static uploads`

## Remove Stackpanel hook after merge

Delete `vendor/alchemy-effect-opennext-overlay/`, `scripts/apply-alchemy-effect-opennext-assets.ts`, root `postinstall`, bump catalog `alchemy-effect` to the release that contains the feature, and run `bun install`.
