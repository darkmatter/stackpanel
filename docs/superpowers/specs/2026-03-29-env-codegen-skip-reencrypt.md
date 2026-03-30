# Env Codegen: Skip Re-encryption When Payload Is Unchanged

## Problem

`packages/gen/env/data/**/*.sops.json` and
`packages/gen/env/src/generated-payloads/**/*.ts` are modified by every
`nix develop` run, even when the underlying env inputs have not changed.

The root cause is unconditional re-encryption: `encryptSopsJSON` is called for
every target on every `preflight run`. AGE encryption is non-deterministic —
the same plaintext produces different ciphertext each time because AGE uses a
random ephemeral key exchange. The SOPS envelope also includes a fresh
`lastmodified` timestamp. As a result, artifact bytes always differ from the
previous run, so the existing byte-compare skip in `writeArtifact` never fires.

This produces two compounding problems:

1. **Flake source tree churn.** Nix identifies the flake input by the hash of
   the source tree. Because checked-in artifacts change on every shell entry,
   the next `nix develop` sees a different input tree and must re-evaluate
   derivations that should have been cached.

2. **Permanently dirty working tree.** Any developer who runs `nix develop`
   will have modified files. New machines, fresh clones, and CI all re-encrypt
   on first run, producing ciphertext that differs from what is committed. The
   files stay dirty until the developer commits or discards them.

## Relationship to the Previous Design (2026-03-23)

The fingerprint design in `2026-03-23-devshell-caching-design.md` stores a
hash of the canonical plaintext in
`~/.local/state/stackpanel/<project>/codegen/env-fingerprints.json`. This
solves problem (1) for a **single developer on a single machine** after the
first run, but does not solve problem (2):

- A developer on a new machine has no fingerprint file.
- After `git pull` on a machine whose fingerprint predates the last pushed
  encryption, the fingerprint is stale.
- In both cases, the first `nix develop` re-encrypts, leaving the working tree
  dirty.

The fingerprint manifest is runtime-local state. The committed ciphertext is
the shared state. Correctness therefore requires deriving the skip decision
from the committed ciphertext, not from a local file.

## Goals

- Stop modifying `packages/gen/env/**` artifacts during `preflight run` when
  the env inputs have not changed, on any machine, without requiring
  coordination between developers.
- Preserve the existing artifact contract: files stay checked in, CI and IDEs
  continue to work without an active devshell.
- Keep the `--force` flag as an escape hatch that bypasses the skip logic.

## Non-Goals

- Removing SOPS or AGE from the encryption pipeline.
- Making SOPS encryption itself deterministic.
- Moving generated artifacts out of the repository.
- Addressing other sources of shell-entry flake churn (`.stack/bin`, logs,
  GC roots) — those are covered by the XDG migration in the previous design.

## Design

### Core Idea

The existing `.sops.json` file encodes the canonical plaintext in encrypted
form. Every developer who holds an AGE key that is a SOPS recipient can
decrypt it. Rather than storing a separate fingerprint, derive the skip
decision from the existing artifact itself:

```
skip encryption if:
  - the output .sops.json file already exists
  - the recipients in its SOPS envelope match the current target recipients
  - decrypt(existing file) == canonical(current resolved plaintext)
```

When all three conditions hold, the committed ciphertext is already an
authoritative encryption of the current plaintext for the current recipient
set. There is no need to produce a new one.

Because this check reads from the committed file rather than from local state,
it produces the same decision on every machine that holds the required AGE key.
The first `nix develop` on a new machine after a `git pull` sees the same
committed ciphertext as all other machines and skips re-encryption identically.

### Canonical Plaintext

The comparison material is the same `[]byte` that `env.go` already constructs:

```go
plaintext, err := json.MarshalIndent(flatEnv, "", "  ")  // sorted keys
plaintext = append(plaintext, '\n')
```

`flatEnv` is a `map[string]string` with deterministic key ordering produced by
`buildFlatEnvPayload`. The canonical serialization is therefore already stable
across runs and machines.

When decrypting the existing artifact, normalize to the same form before
comparing:

1. Run `sops --decrypt --output-type json <outputPath>`.
2. Unmarshal into `map[string]any`.
3. Coerce values with `stringifyEnvValue` (the existing helper) to produce
   `map[string]string`.
4. Marshal with `json.MarshalIndent(..., "", "  ")` + trailing newline.
5. Compare bytes.

This round-trip is safe: the only values stored in a payload `.sops.json` are
`string` scalars originating from `buildFlatEnvPayload`, so `stringifyEnvValue`
is a no-op. The step is included for correctness in case the file was produced
by a future format revision.

### Recipient Matching

The SOPS envelope in a `.sops.json` file includes an `age` block:

```json
{
  "sops": {
    "age": [
      { "recipient": "age1...", "enc": "..." },
      ...
    ]
  }
}
```

Extract the `recipient` strings, sort them, and compare against
`sort(target.Recipients)`. If the sets differ — because a team member was
added or removed — treat the file as stale and re-encrypt regardless of
plaintext equality.

### Decryption Failure

If `sops --decrypt` fails (e.g., the current developer's AGE key is not yet a
recipient in the existing file), the skip check cannot complete. Fall through
to re-encryption. This is the correct behavior: the new recipient needs a
fresh encryption that includes their key.

### TS Module

`renderGeneratedPayloadModule` wraps the encrypted bytes as a string constant.
If encryption is skipped, the ciphertext bytes are identical to what is on
disk. The existing `writeArtifact` byte-compare will then skip the TS module
write too. No additional logic is needed.

## Implementation

### New helper: `payloadIsUpToDate`

Add a function to `env.go` with the signature:

```go
func payloadIsUpToDate(
    ctx context.Context,
    projectRoot string,
    outputPath string,
    canonicalPlaintext []byte,
    recipients []string,
) (bool, error)
```

Steps:

1. `os.Stat(outputPath)` — if the file does not exist, return `(false, nil)`.
2. Read the file and parse the raw JSON to extract `sops.age[*].recipient`
   strings. Sort them. Compare against `sort(recipients)`. If they differ,
   return `(false, nil)`.
3. Run `sops --decrypt --output-type json outputPath`. If the command fails,
   log a debug note and return `(false, nil)` (fall through to re-encrypt).
4. Unmarshal, coerce with `stringifyEnvValue`, re-marshal with `MarshalIndent`
   + trailing newline.
5. `bytes.Equal(normalized, canonicalPlaintext)`. Return `(result, nil)`.

### Changes to `Build` in `env.go`

In the target loop, after producing `plaintext` and before calling
`encryptSopsJSON`:

```go
outputPath := resolveProjectPath(req.ProjectRoot, target.OutputPath)

if !req.Force {
    upToDate, err := payloadIsUpToDate(ctx, req.ProjectRoot, outputPath, plaintext, target.Recipients)
    if err != nil {
        return nil, fmt.Errorf("check %s/%s payload: %w", target.App, target.Environment, err)
    }
    if upToDate {
        existing, err := os.ReadFile(outputPath)
        if err != nil {
            return nil, fmt.Errorf("read existing %s/%s payload: %w", target.App, target.Environment, err)
        }
        // Reuse the committed ciphertext. writeArtifact will byte-compare
        // and skip the write; the TS module write will also be skipped.
        encrypted = existing
        goto emitArtifacts
    }
}

encrypted, err = encryptSopsJSON(ctx, req.ProjectRoot, plaintext, outputPath, target.Recipients)
// ...

emitArtifacts:
// emit sops.json and TS module artifacts as before
```

(The `goto` can be replaced with an `else` block or a helper function per team
preference.)

### `BuildRequest.Force`

The existing `Force bool` field on `BuildRequest` is already threaded through
from `preflight run --force`. The new check is skipped entirely when
`req.Force` is true.

## Behaviour Table

| Condition | Outcome |
|---|---|
| First run, no existing artifact | Encrypt and write (cold start) |
| Artifact exists, plaintext unchanged, recipients unchanged | Skip encryption, skip write |
| Artifact exists, plaintext changed | Re-encrypt and write |
| Artifact exists, recipients changed (team member added/removed) | Re-encrypt and write |
| Artifact exists, decryption fails (key not a recipient) | Re-encrypt and write |
| `--force` flag set | Re-encrypt and write unconditionally |

## Risks and Mitigations

### Risk: canonical form drift

If the serialization of `flatEnv` changes in a future version of the codegen
(different indentation, key order, type coercion), the round-tripped form from
the decrypted file will no longer match the freshly computed form, causing
unnecessary re-encryption on the first run after an upgrade.

Mitigation: the skip logic treats mismatches as a reason to re-encrypt, which
is safe. The only observable effect is one extra encryption on upgrade. No
stale artifact is ever retained.

### Risk: partial recipient extraction

If the SOPS envelope format changes in a future SOPS version, extracting
`sops.age[*].recipient` by JSON field access could fail silently and return an
empty set, causing a recipient mismatch even when none exists.

Mitigation: if the recipient extraction step produces an empty slice when
`target.Recipients` is non-empty, treat as a mismatch and re-encrypt.

### Risk: decryption side-effects

Calling `sops --decrypt` on the existing artifact during skip-check adds one
subprocess invocation per target per `preflight run`. For a project with many
targets, this could add measurable latency.

Mitigation: the decrypt-cache (`decryptCache`) already used for source file
decryption can be extended to cache output artifact decryption by path, so
repeated calls within one `preflight run` pay the cost only once. In practice
the number of targets is small (one per app/environment pair).

### Risk: key rotation

If an AGE key is rotated (old key revoked, new key issued), the existing
ciphertext cannot be decrypted with the new key. Decryption fails → skip check
returns `(false, nil)` → re-encryption runs → new ciphertext uses new key.
This is the correct and desired behaviour.

## Verification

After implementation, verify all of the following:

1. Repeated `nix develop --impure -c which aws` on the same machine with
   unchanged secrets does not modify any file under `packages/gen/env/`.
2. `git status` shows no modified files after a clean `nix develop` run.
3. `nix flake archive --json .` before and after a `nix develop` round-trip
   produces the same flake source path when secrets are unchanged.
4. On a fresh clone (no prior `preflight run`), the first `nix develop`
   re-encrypts and writes artifacts; subsequent runs skip.
5. After a team member's AGE key is added to recipients, the next
   `nix develop` re-encrypts all affected targets.
6. After a real secret value is changed, the corresponding artifacts are
   re-encrypted and rewritten.
7. `preflight run --force` always re-encrypts regardless of state.
