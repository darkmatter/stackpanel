# Devshell Caching and Runtime State Isolation

## Problem

`nix develop --impure -c ...` is slow on repeated runs in this repository.

Two behaviors combine to cause the slowdown:

1. Shell entry mutates files inside the flake source tree.
2. Env codegen re-encrypts tracked payload files on every shell entry, even when the resolved plaintext did not change.

Because the local flake input changes after shell entry, the next `nix develop` sees a different source tree and rebuilds derivations that should have been reused.

## Goals

- Keep `stackpanel preflight run` enabled on shell entry.
- Keep checked-in env artifacts under `packages/gen/env/...`.
- Make repeated `nix develop --impure -c ...` runs fast when config and resolved env inputs are unchanged.
- Ensure ordinary shell entry does not mutate the flake input tree.
- Preserve current behavior when env inputs actually change.

## Non-Goals

- Removing preflight from shell entry.
- Moving checked-in env artifacts out of the repository.
- Fully redesigning the broader generated-files system.
- Eliminating `--impure` in this change.

## Root Cause Summary

Current shell entry performs both repo-owned generation and runtime bookkeeping in or under the repository root.

The highest-impact churn comes from env codegen:

- preflight resolves env inputs
- canonical plaintext is produced
- `sops --encrypt` is run every time
- encrypted `.sops.json` artifacts are rewritten
- generated TypeScript payload modules are rewritten from the new ciphertext

Since SOPS emits fresh ciphertext and metadata such as `lastmodified`, the tracked artifacts change even when the underlying plaintext env payload did not.

Additional runtime-only outputs also change during shell entry, including mutable state under `.stack/profile`, `.stack/bin`, logs, and GC root bookkeeping.

## Design Overview

Split shell-entry outputs into two classes:

1. **Tracked project artifacts**
   - Intended to live in the repository.
   - Example: `packages/gen/env/data/...`, `packages/gen/env/src/generated-payloads/...`, checked-in `.stack/gen/...` artifacts.
   - These should change only when their logical inputs change.

2. **Runtime state**
   - Mutable shell-entry outputs that should not affect flake identity.
   - Example: logs, GC roots, generated bin symlink farms, transient manifests, shell bookkeeping.
   - These move to XDG-style user locations outside the repository.

## Runtime State Locations

Use XDG-style per-project directories keyed by project identity.

- Cache: `~/.cache/stackpanel/<project>`
- State: `~/.local/state/stackpanel/<project>`

Recommended split:

- `~/.cache/stackpanel/<project>`
  - disposable caches
  - generated bin/link farms
  - recomputable helper outputs

- `~/.local/state/stackpanel/<project>`
  - shell logs
  - GC roots and generation bookkeeping
  - preflight fingerprints/manifests
  - other mutable state that should survive across shell entries

The repository should no longer be the default home for runtime-only outputs.

## Env Codegen Fingerprinting

### Intent

Keep checked-in env artifacts, but stop rewriting them unless their logical contents changed.

### Per-target fingerprint

For each env target (`app` + `environment`), compute a deterministic fingerprint from:

- canonical plaintext payload JSON with stable key ordering
- sorted recipient list
- target identity (`app`, `environment`, and output path)
- codegen schema/version marker

The fingerprint is stored in runtime state, not in the repository.

### Canonical plaintext

Before any encryption step:

1. resolve/decrypt all source inputs
2. produce a flat env payload map
3. serialize to canonical JSON with sorted keys and stable formatting

This canonical plaintext is the logical content that determines whether tracked outputs should change.

### Shell-entry behavior

For each target:

1. compute the canonical plaintext and target fingerprint
2. load the previously saved fingerprint record from runtime state
3. verify that the expected checked-in outputs still exist
4. if fingerprint matches and outputs exist, skip encryption and skip rewriting tracked artifacts
5. if fingerprint differs, or an expected tracked output is missing, run encryption and rewrite tracked artifacts
6. update the runtime fingerprint record

### Why this works

The tracked `.sops.json` files remain checked in, but they stop changing when their underlying plaintext and recipients are unchanged.

That removes the largest source of shell-entry mutation in the flake source tree while preserving the current artifact contract.

## Fingerprint Manifest Format

Add a runtime manifest under the state directory, for example:

`~/.local/state/stackpanel/<project>/codegen/env-fingerprints.json`

Suggested structure:

```json
{
  "schemaVersion": 1,
  "targets": {
    "docs:dev": {
      "fingerprint": "sha256:...",
      "artifactPaths": [
        "packages/gen/env/data/dev/docs.sops.json",
        "packages/gen/env/src/generated-payloads/docs/dev.ts"
      ]
    }
  }
}
```

The manifest is runtime state only. It is not checked in.

## Runtime Path Migration

Update shell hooks and helper scripts to use explicit runtime directories instead of repo-local mutable defaults.

Introduce or standardize environment variables such as:

- `STACKPANEL_CACHE_DIR`
- `STACKPANEL_STATE_DIR`

Then migrate runtime-writing components to use those variables by default.

Priority candidates:

- `.stack/bin` generation
- shell logs
- GC roots/generation state
- transient preflight state and manifests that do not need to be committed

Repo-local checked-in generated artifacts remain where they are.

## Compatibility Strategy

- Keep current repo paths working temporarily when explicitly configured.
- Default new shells to XDG runtime locations.
- If old repo-local runtime directories exist, leave them alone or optionally clean them up with a separate maintenance path.
- Avoid symlinking mutable runtime state back into the repository, since that would weaken isolation and reintroduce churn.

## Implementation Notes

### Env codegen

- Build the fingerprint from plaintext inputs before `sops --encrypt`.
- Skip encryption when fingerprint and artifact existence checks pass.
- Continue writing the generated TypeScript payload module only when ciphertext actually needs to be refreshed.
- Preserve the current behavior for stale artifact cleanup.

### Runtime outputs

- Move repo-local runtime defaults into XDG state/cache locations.
- Ensure code paths that currently assume `.stack/profile/...` are updated to read the new runtime env vars.
- Keep checked-in `.stack/gen/...` artifacts separate from runtime state.

## Risks and Mitigations

### Risk: fingerprint misses a logical input

If the fingerprint excludes an input that changes output semantics, codegen may incorrectly skip a rewrite.

Mitigation:

- include plaintext payload, recipients, target identity, and explicit schema/version marker
- keep the manifest versioned so additional inputs can be added safely later

### Risk: missing checked-in outputs with matching fingerprint

If a user deletes a checked-in generated file, fingerprint equality alone would skip regeneration.

Mitigation:

- require artifact existence checks in addition to fingerprint equality

### Risk: partial migration leaves hidden repo churn

Some shell-entry writers may still target repo-local paths.

Mitigation:

- audit all shell-entry writers and classify them as tracked artifact vs runtime state
- verify with repeated `nix flake archive --json .` and repeated `nix develop --impure -c ...`

## Verification Plan

After implementation, verify all of the following:

1. Repeated `nix flake archive --json .` around shell entry yields the same flake source path when no logical inputs changed.
2. Repeated `nix develop --impure -c which aws` shows the second run is substantially faster.
3. Repeated shell entry with unchanged env inputs does not modify checked-in `packages/gen/env/data/...` or `packages/gen/env/src/generated-payloads/...` files.
4. Changing a real env input causes the corresponding checked-in artifacts to refresh.
5. Runtime-only files are written under XDG state/cache paths instead of the repository.

## Follow-On Work

This design intentionally leaves one adjacent optimization for later:

- add checksums to the generated manifest inputs so preflight can skip more work earlier, before even reaching some codegen paths

That is complementary to this design, but not required for the initial fix.
