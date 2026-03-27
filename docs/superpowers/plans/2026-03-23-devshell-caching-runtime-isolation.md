# Devshell Caching and Runtime State Isolation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make repeated `nix develop --impure -c ...` runs reuse prior work by preventing repo-local runtime churn, skipping secret/env decrypt work when encrypted inputs are unchanged, and skipping env re-encryption when logical plaintext is unchanged.

**Architecture:** Add a two-tier per-target env cache in Go codegen, stored under XDG runtime state keyed by project name plus a short root-path hash. Tier 1 stores a cheap encrypted-input stamp so shell entry can skip decrypting secrets when the encrypted source inputs and resolver config are unchanged; Tier 2 stores a canonical plaintext fingerprint so even when decryption is required, Stackpanel only rewrites checked-in artifacts if the logical env payload changed. Update shell/Nix/CLI runtime-path plumbing so mutable state lives under `XDG_CACHE_HOME` / `XDG_STATE_HOME` while checked-in generated artifacts stay in the repo, and add an optional process-compose watcher for secrets codegen so `dev` can refresh them live. Follow the same separation of cache and runtime state used by `cachix/devenv`'s task runner (`cache_dir` vs `runtime_dir`), but keep Stackpanel's existing preflight flow.

**Tech Stack:** Go (Cobra CLI, codegen, fileops), Nix modules and shell hooks, shell scripts, XDG base directory conventions, SOPS.

---

## File Map

- `apps/stackpanel-go/pkg/runtimepaths/runtimepaths.go` - shared Go helper that derives `STACKPANEL_RUNTIME_KEY`, `STACKPANEL_CACHE_DIR`, `STACKPANEL_STATE_DIR`, and shell-log paths from env + project root.
- `apps/stackpanel-go/pkg/runtimepaths/runtimepaths_test.go` - unit tests for runtime-key derivation and XDG fallback behavior.
- `apps/stackpanel-go/internal/codegen/env_fingerprint.go` - encrypted-input stamp hashing, canonical payload hashing, cache-manifest load/save, and artifact-existence checks.
- `apps/stackpanel-go/internal/codegen/env_fingerprint_test.go` - unit tests for encrypted-input stamps, canonical hashing, and cache-manifest behavior.
- `apps/stackpanel-go/internal/codegen/env.go` - env module integration: cheap skip before decrypt, plaintext fingerprint after decrypt, no-op rewrite avoidance, regenerate when artifacts are missing.
- `apps/stackpanel-go/internal/codegen/builder_test.go` - regression tests for repeated builds skipping unchanged artifacts.
- `apps/stackpanel-go/cmd/cli/preflight.go` - use shared runtime-path resolution instead of repo-local `.stack/profile` fallback.
- `apps/stackpanel-go/cmd/cli/logs.go` - locate shell logs via shared runtime-path helper.
- `apps/stackpanel-go/pkg/envvars/envvars.go` - document/export new runtime env vars (`STACKPANEL_RUNTIME_KEY`, `STACKPANEL_CACHE_DIR`) and update path descriptions.
- `nix/stackpanel/core/lib/envvars/sections.nix` - keep Nix-side env-var metadata in sync with Go.
- `nix/stackpanel/lib/paths.nix` - central shell-path utility changes: derive XDG runtime dirs from project name + root hash while keeping repo-owned dirs (`.stack/gen`, `.stack/keys`) unchanged.
- `nix/stackpanel/core/default.nix` - shell startup/log messaging should use the new runtime state location.
- `nix/stackpanel/core/cli.nix` - write `stackpanel.json` to the XDG state dir and keep shell hooks exporting the new runtime vars.
- `nix/stackpanel/core/options/devshell.nix` - preserve `XDG_CACHE_HOME` and `XDG_STATE_HOME` in clean-shell mode by default.
- `nix/stackpanel/devshell/default.nix` - standalone devshell path defaults should match the main shell-path behavior.
- `nix/stackpanel/devshell/bin.nix` - move the generated bin symlink farm from `.stack/bin` to `STACKPANEL_CACHE_DIR/bin`.
- `nix/stackpanel/devshell/gc-roots.nix` - keep GC roots under the XDG state dir.
- `nix/stackpanel/devshell/clean.nix` - `./devshell --logs` and direnv hints should read shell logs from the new runtime location.
- `nix/stackpanel/files/default.nix` - keep file-writer manifests under `STACKPANEL_STATE_DIR` only, not repo-local fallbacks.
- `nix/stackpanel/modules/process-compose/module.nix` - add an optional infra watcher process that reruns secrets/env codegen when relevant files change.
- `nix/stackpanel/modules/process-compose.test.nix` - focused module test coverage for the new optional secrets watcher.

## Task 1: Add Shared Runtime-Path Plumbing

**Files:**
- Create: `apps/stackpanel-go/pkg/runtimepaths/runtimepaths.go`
- Test: `apps/stackpanel-go/pkg/runtimepaths/runtimepaths_test.go`
- Modify: `apps/stackpanel-go/cmd/cli/preflight.go`
- Modify: `apps/stackpanel-go/cmd/cli/logs.go`
- Modify: `apps/stackpanel-go/pkg/envvars/envvars.go`
- Modify: `nix/stackpanel/lib/paths.nix`
- Modify: `nix/stackpanel/core/default.nix`
- Modify: `nix/stackpanel/core/cli.nix`
- Modify: `nix/stackpanel/core/lib/envvars/sections.nix`
- Modify: `nix/stackpanel/core/options/devshell.nix`
- Modify: `nix/stackpanel/devshell/default.nix`

- [ ] **Step 1: Write the failing Go tests for runtime-key and XDG path derivation**

```go
func TestDirsUseXDGLocationsAndProjectHash(t *testing.T) {
    t.Setenv("XDG_CACHE_HOME", "/tmp/cache-home")
    t.Setenv("XDG_STATE_HOME", "/tmp/state-home")
    dirs := Resolve("/repo/root", "stackpanel")

    if !strings.HasPrefix(dirs.CacheDir, "/tmp/cache-home/stackpanel/") {
        t.Fatalf("cache dir = %q", dirs.CacheDir)
    }
    if !strings.HasPrefix(dirs.StateDir, "/tmp/state-home/stackpanel/") {
        t.Fatalf("state dir = %q", dirs.StateDir)
    }
    if !strings.HasPrefix(dirs.RuntimeKey, "stackpanel-") {
        t.Fatalf("runtime key = %q", dirs.RuntimeKey)
    }
}

func TestDirsFallBackWhenProjectNameMissing(t *testing.T) {
    dirs := Resolve("/repo/root", "")
    if dirs.RuntimeKey == "" || dirs.StateDir == "" || dirs.CacheDir == "" {
        t.Fatal("expected fallback runtime paths")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/stackpanel-go && go test ./pkg/runtimepaths -run TestDirs -count=1`
Expected: FAIL with missing package or undefined `Resolve`

- [ ] **Step 3: Implement the shared runtime-path helper**

```go
type Dirs struct {
    RuntimeKey string
    CacheDir   string
    StateDir   string
    ShellLog   string
}

func Resolve(projectRoot, projectName string) Dirs {
    normalizedName := firstNonEmpty(projectName, filepath.Base(projectRoot), "stackpanel")
    suffix := shortMD5(projectRoot)
    key := normalizedName + "-" + suffix
    cacheHome := firstNonEmpty(os.Getenv("XDG_CACHE_HOME"), filepath.Join(homeDir(), ".cache"))
    stateHome := firstNonEmpty(os.Getenv("XDG_STATE_HOME"), filepath.Join(homeDir(), ".local", "state"))
    return Dirs{
        RuntimeKey: key,
        CacheDir:   filepath.Join(cacheHome, "stackpanel", key),
        StateDir:   filepath.Join(stateHome, "stackpanel", key),
        ShellLog:   filepath.Join(stateHome, "stackpanel", key, "shell.log"),
    }
}
```

- [ ] **Step 4: Re-run the Go tests to verify they pass**

Run: `cd apps/stackpanel-go && go test ./pkg/runtimepaths -run TestDirs -count=1`
Expected: PASS

- [ ] **Step 5: Wire shell startup to export the same runtime vars**

Implementation notes:

- In `nix/stackpanel/lib/paths.nix`, derive `STACKPANEL_RUNTIME_KEY`, `STACKPANEL_CACHE_DIR`, and `STACKPANEL_STATE_DIR` from `STACKPANEL_PROJECT_NAME`, `STACKPANEL_ROOT`, and XDG defaults.
- Keep `.stack/gen` and `.stack/keys` repo-local.
- Let explicit env overrides win so users can still force repo-local runtime dirs if needed.
- Make `runtimepaths.Resolve(...)` honor `STACKPANEL_CACHE_DIR` / `STACKPANEL_STATE_DIR` overrides before falling back to XDG-derived paths so Go-side behavior matches shell-side behavior.
- In `nix/stackpanel/core/options/devshell.nix`, add `config.stackpanel.devshell.clean.keepXdg` into the default preserved env list so clean shells keep `XDG_CACHE_HOME` and `XDG_STATE_HOME`.
- Update `apps/stackpanel-go/cmd/cli/preflight.go` and `apps/stackpanel-go/cmd/cli/logs.go` to use `runtimepaths.Resolve(...)` instead of hardcoding `.stack/profile`.

- [ ] **Step 6: Verify the exported values from `nix develop`**

Run:

```bash
nix develop --impure -c bash -lc 'printf "%s\n" "$STACKPANEL_RUNTIME_KEY" "$STACKPANEL_CACHE_DIR" "$STACKPANEL_STATE_DIR"'
```

Expected:

- the runtime key starts with `stackpanel-`
- cache dir is under `${XDG_CACHE_HOME:-$HOME/.cache}/stackpanel/...`
- state dir is under `${XDG_STATE_HOME:-$HOME/.local/state}/stackpanel/...`

- [ ] **Step 7: Commit**

```bash
git add apps/stackpanel-go/pkg/runtimepaths/runtimepaths.go apps/stackpanel-go/pkg/runtimepaths/runtimepaths_test.go apps/stackpanel-go/cmd/cli/preflight.go apps/stackpanel-go/cmd/cli/logs.go apps/stackpanel-go/pkg/envvars/envvars.go nix/stackpanel/lib/paths.nix nix/stackpanel/core/default.nix nix/stackpanel/core/cli.nix nix/stackpanel/core/lib/envvars/sections.nix nix/stackpanel/core/options/devshell.nix nix/stackpanel/devshell/default.nix
git commit -m "refactor: move shell runtime paths to XDG dirs"
```

## Task 2: Add Two-Tier Env Cache Helpers

**Files:**
- Create: `apps/stackpanel-go/internal/codegen/env_fingerprint.go`
- Test: `apps/stackpanel-go/internal/codegen/env_fingerprint_test.go`

- [ ] **Step 1: Write the failing tests for encrypted-input stamps, canonical hashing, and manifest persistence**

```go
func TestEnvInputStampChangesWhenEncryptedSourceChanges(t *testing.T) {
    left := envInputStampRequest{
        TargetKey:   "docs:dev",
        OutputPath:  "packages/gen/env/data/dev/docs.sops.json",
        Recipients:  []string{"r2", "r1"},
        ResolverConfig: map[string]string{"moduleVersion": "1", "format": "sops-json"},
        SourceFiles: map[string]string{"a.sops.json": "cipher-1"},
    }
    right := envInputStampRequest{
        TargetKey:   "docs:dev",
        OutputPath:  "packages/gen/env/data/dev/docs.sops.json",
        Recipients:  []string{"r1", "r2"},
        ResolverConfig: map[string]string{"moduleVersion": "1", "format": "sops-json"},
        SourceFiles: map[string]string{"a.sops.json": "cipher-2"},
    }

    if inputStampEnvTarget(left) == inputStampEnvTarget(right) {
        t.Fatal("expected encrypted input change to alter stamp")
    }
}

func TestEnvFingerprintIgnoresMapInsertionOrder(t *testing.T) {
    left := map[string]string{"A": "1", "B": "2"}
    right := map[string]string{"B": "2", "A": "1"}

    if fingerprintEnvTarget("docs", "dev", "out.json", []string{"r2", "r1"}, left) !=
        fingerprintEnvTarget("docs", "dev", "out.json", []string{"r1", "r2"}, right) {
        t.Fatal("expected canonical fingerprint")
    }
}

func TestEnvFingerprintManifestRoundTrip(t *testing.T) {
    path := filepath.Join(t.TempDir(), "env-fingerprints.json")
    want := envFingerprintManifest{SchemaVersion: 1, Targets: map[string]envFingerprintRecord{
        "docs:dev": {
            InputStamp:           "sha256:encrypted",
            PlaintextFingerprint: "sha256:plaintext",
            ArtifactPaths:        []string{"a", "b"},
        },
    }}
    require.NoError(t, saveEnvFingerprintManifest(path, want))
    got, err := loadEnvFingerprintManifest(path)
    require.NoError(t, err)
    require.Equal(t, want, got)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/stackpanel-go && go test ./internal/codegen -run 'TestEnv(InputStamp|Fingerprint)' -count=1`
Expected: FAIL with undefined helpers/types

- [ ] **Step 3: Implement encrypted-input stamp, canonical fingerprint, and manifest helpers**

```go
type envInputStampRequest struct {
    TargetKey      string
    OutputPath     string
    Recipients     []string
    ResolverConfig map[string]string
    SourceFiles    map[string]string
}

type envFingerprintRecord struct {
    InputStamp           string   `json:"inputStamp"`
    PlaintextFingerprint string   `json:"plaintextFingerprint"`
    ArtifactPaths        []string `json:"artifactPaths"`
}

type envFingerprintManifest struct {
    SchemaVersion int                            `json:"schemaVersion"`
    Targets       map[string]envFingerprintRecord `json:"targets"`
}

func inputStampEnvTarget(req envInputStampRequest) string {
    // sort source file paths, resolver-config keys, recipients, and hash
    // encrypted bytes + target identity + output path + cheap-skip config + version marker
}

func fingerprintEnvTarget(app, env, outputPath string, recipients []string, payload map[string]string) string {
    // sort payload keys, sort recipients, serialize canonical JSON, sha256 it
}
```

Implementation notes:

- Store the manifest under `filepath.Join(runtimepaths.Resolve(projectRoot, projectName).StateDir, "codegen", "env-fingerprints.json")`.
- Include target identity, output path, recipients, cheap resolver config, and a hardcoded schema/version marker in the encrypted-input stamp.
- Include a hardcoded schema/version marker in both the encrypted-input stamp and plaintext fingerprint inputs so future output-affecting changes can invalidate old cache records intentionally.
- Sort `ArtifactPaths` before writing to keep the manifest stable.

- [ ] **Step 4: Re-run the tests to verify they pass**

Run: `cd apps/stackpanel-go && go test ./internal/codegen -run 'TestEnv(InputStamp|Fingerprint)' -count=1`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/stackpanel-go/internal/codegen/env_fingerprint.go apps/stackpanel-go/internal/codegen/env_fingerprint_test.go
git commit -m "feat: add two-tier env codegen cache metadata"
```

## Task 3: Integrate Two-Tier Caching Into Env Codegen

**Files:**
- Modify: `apps/stackpanel-go/internal/codegen/env.go`
- Modify: `apps/stackpanel-go/internal/codegen/builder_test.go`
- Modify: `apps/stackpanel-go/cmd/cli/codegen.go`

- [ ] **Step 1: Write the failing regression tests for cheap no-op skips and plaintext no-op rewrites**

```go
func TestBuilderSkipsEnvModuleWithoutDecryptWhenInputStampMatches(t *testing.T) {
    projectRoot := t.TempDir()
    stateHome := t.TempDir()
    t.Setenv("XDG_STATE_HOME", stateHome)
    t.Setenv("STACKPANEL_PROJECT_NAME", "stackpanel")

    fake := installFakeSops(t, projectRoot, map[string]string{
        "decrypt": `{"HOSTNAME":"docs.local","PORT":"5738"}`,
        "encrypt": `{"ciphertext":"first"}`,
    })

    builder := NewBuilder(DefaultRegistry())
    _, err := builder.Build(context.Background(), projectRoot, []string{envModuleName}, false, false)
    require.NoError(t, err)
    fake.ResetCounters()

    second, err := builder.Build(context.Background(), projectRoot, []string{envModuleName}, false, false)
    require.NoError(t, err)
    require.NotEmpty(t, second.Results[0].Skipped)
    require.Zero(t, fake.DecryptCalls())
}

func TestBuilderSkipsRewriteWhenEncryptedInputChangedButPlaintextDidNot(t *testing.T) {
    projectRoot := t.TempDir()
    stateHome := t.TempDir()
    t.Setenv("XDG_STATE_HOME", stateHome)
    t.Setenv("STACKPANEL_PROJECT_NAME", "stackpanel")

    fake := installFakeSops(t, projectRoot, map[string]string{
        "decrypt": `{"HOSTNAME":"docs.local","PORT":"5738"}`,
        "encrypt": `{"ciphertext":"first"}`,
    })

    builder := NewBuilder(DefaultRegistry())
    _, err := builder.Build(context.Background(), projectRoot, []string{envModuleName}, false, false)
    require.NoError(t, err)

    rewriteEncryptedSourceWithoutChangingPlaintext(t, projectRoot)
    fake.SetEncryptResponse(`{"ciphertext":"second"}`)
    fake.ResetCounters()

    second, err := builder.Build(context.Background(), projectRoot, []string{envModuleName}, false, false)
    require.NoError(t, err)
    require.Equal(t, 1, fake.DecryptCalls())
    require.Zero(t, fake.EncryptCalls())
    require.Empty(t, second.Results[0].Files)
    require.NotEmpty(t, second.Results[0].Notes)
}

func TestBuilderRebuildsEnvModuleWhenArtifactMissing(t *testing.T) {
    projectRoot := t.TempDir()
    stateHome := t.TempDir()
    t.Setenv("XDG_STATE_HOME", stateHome)
    t.Setenv("STACKPANEL_PROJECT_NAME", "stackpanel")

    installFakeSops(t, projectRoot, map[string]string{
        "decrypt": `{"HOSTNAME":"docs.local","PORT":"5738"}`,
        "encrypt": `{"ciphertext":"first"}`,
    })

    builder := NewBuilder(DefaultRegistry())
    _, err := builder.Build(context.Background(), projectRoot, []string{envModuleName}, false, false)
    require.NoError(t, err)

    missingPath := filepath.Join(projectRoot, "packages/gen/env/src/generated-payloads/docs/dev.ts")
    require.NoError(t, os.Remove(missingPath))

    second, err := builder.Build(context.Background(), projectRoot, []string{envModuleName}, false, false)
    require.NoError(t, err)
    require.Contains(t, second.Results[0].Files, missingPath)
}
```

- [ ] **Step 2: Run the regression tests to verify they fail**

Run: `cd apps/stackpanel-go && go test ./internal/codegen -run 'TestBuilder(SkipsEnvModuleWithoutDecrypt|SkipsRewriteWhenEncryptedInputChangedButPlaintextDidNot|RebuildsEnvModule)' -count=1`
Expected: FAIL because the env module still decrypts and re-encrypts more often than necessary

- [ ] **Step 3: Implement two-tier skip behavior in `env.go`**

Implementation notes:

- Resolve runtime dirs via `runtimepaths.Resolve(projectRoot, os.Getenv("STACKPANEL_PROJECT_NAME"))`.
- Before decrypting, compute the encrypted-input stamp from the encrypted source files, recipient list, target identity, output path, cheap resolver config, and version marker.
- Load the manifest and, if the input stamp matches and all expected artifacts exist, skip decrypt and skip rewriting tracked artifacts entirely.
- When the cheap skip path is taken, add a `BuildResult.Notes` entry such as `skipped decrypt for docs:dev (input stamp match)` so manual verification can confirm the behavior.
- Only when the input stamp differs or artifacts are missing, decrypt and build canonical plaintext, then compute the plaintext fingerprint.
- If plaintext fingerprint matches and artifacts exist, update the runtime manifest with the new input stamp but skip `sops --encrypt` and skip rewriting tracked artifacts.
- If plaintext fingerprint differs or artifacts are missing, run `sops --encrypt`, write both the checked-in `.sops.json` file and the generated TS payload, then update the manifest with both cache fields.
- Keep stale-artifact removal behavior intact.
- Update `apps/stackpanel-go/cmd/cli/codegen.go` summary output so those `BuildResult.Notes` entries are visible in normal or verbose runs used for verification.

- [ ] **Step 4: Re-run the env codegen test suite to verify it passes**

Run: `cd apps/stackpanel-go && go test ./internal/codegen -count=1`
Expected: PASS

- [ ] **Step 5: Verify the module skips unchanged env artifacts in practice**

Run:

```bash
git status --short -- packages/gen/env
nix develop --impure -c true >/tmp/stackpanel-preflight-1.log 2>&1
git status --short -- packages/gen/env
nix develop --impure -c true >/tmp/stackpanel-preflight-2.log 2>&1
git status --short -- packages/gen/env
```

Expected:

- after the first run, files may be written once
- after the second run with unchanged encrypted inputs, `packages/gen/env/...` stays unchanged and no decrypt work is needed
- after a re-encryption-only change to a secret source, `packages/gen/env/...` still stays unchanged

- [ ] **Step 6: Commit**

```bash
git add apps/stackpanel-go/internal/codegen/env.go apps/stackpanel-go/internal/codegen/builder_test.go apps/stackpanel-go/cmd/cli/codegen.go
git commit -m "fix: avoid unnecessary secret decrypts and env rewrites"
```

## Task 4: Move Runtime Writers Out of the Repo Tree

**Files:**
- Modify: `nix/stackpanel/devshell/bin.nix`
- Modify: `nix/stackpanel/devshell/gc-roots.nix`
- Modify: `nix/stackpanel/files/default.nix`
- Modify: `nix/stackpanel/devshell/clean.nix`
- Modify: `nix/stackpanel/core/default.nix`

- [ ] **Step 1: Write the smallest regression test for the user-visible path lookup**

```go
func TestShellLogPathFollowsRuntimeStateDir(t *testing.T) {
    t.Setenv("STACKPANEL_STATE_DIR", "/tmp/stackpanel-state")
    if got := runtimepaths.Resolve("/repo/root", "stackpanel").ShellLog; !strings.Contains(got, "/tmp/stackpanel-state") {
        t.Fatalf("shell log path = %q", got)
    }
}
```

Add this to `apps/stackpanel-go/pkg/runtimepaths/runtimepaths_test.go` if it does not already exist.

- [ ] **Step 2: Run the targeted test to verify it fails if needed**

Run: `cd apps/stackpanel-go && go test ./pkg/runtimepaths -run TestShellLogPath -count=1`
Expected: FAIL only if the override path has not been implemented yet; otherwise skip this step as already satisfied by Task 1.

- [ ] **Step 3: Move mutable runtime outputs to cache/state dirs**

Implementation notes:

- In `nix/stackpanel/devshell/bin.nix`, use `BIN_DIR="${STACKPANEL_CACHE_DIR}/bin"` and update any PATH prepend to the same location.
- In `nix/stackpanel/devshell/gc-roots.nix`, keep GC roots under `"${STACKPANEL_STATE_DIR}/gc"` with no repo-local fallback.
- In `nix/stackpanel/files/default.nix`, treat `STACKPANEL_STATE_DIR` as the only manifest home during shell entry.
- In `nix/stackpanel/devshell/clean.nix`, compute the same runtime key and shell-log path before `--logs` / direnv hints so the wrapper still works outside an active shell.
- Make the wrapper respect explicit `STACKPANEL_CACHE_DIR` / `STACKPANEL_STATE_DIR` overrides before computing XDG defaults.
- In `nix/stackpanel/core/default.nix`, update user-facing “Log saved to ...” messages to print the XDG-backed log path.

- [ ] **Step 4: Re-run the targeted Go test if Step 2 failed**

Run: `cd apps/stackpanel-go && go test ./pkg/runtimepaths -run TestShellLogPath -count=1`
Expected: PASS

- [ ] **Step 5: Verify runtime churn moved off-repo**

Run:

```bash
python - <<'PY'
import json, os, pathlib, subprocess
root = pathlib.Path('.').resolve()
before = subprocess.check_output(['git', 'status', '--porcelain=v1'], text=True)
subprocess.run(['nix', 'develop', '--impure', '-c', 'true'], check=False)
after = subprocess.check_output(['git', 'status', '--porcelain=v1'], text=True)
print(before)
print(after)
print('cache dir:', os.environ.get('XDG_CACHE_HOME', str(pathlib.Path.home()/'.cache')))
print('state dir:', os.environ.get('XDG_STATE_HOME', str(pathlib.Path.home()/'.local/state')))
PY
```

Expected:

- repo-local `.stack/bin`, `.stack/profile/gc`, and shell-log churn no longer appear as changed paths
- mutable files show up under the XDG cache/state trees instead

- [ ] **Step 6: Commit**

```bash
git add nix/stackpanel/devshell/bin.nix nix/stackpanel/devshell/gc-roots.nix nix/stackpanel/files/default.nix nix/stackpanel/devshell/clean.nix nix/stackpanel/core/default.nix apps/stackpanel-go/pkg/runtimepaths/runtimepaths_test.go
git commit -m "refactor: move runtime shell outputs off-repo"
```

## Task 5: Add Optional Secrets Watcher for `dev`

**Files:**
- Modify: `nix/stackpanel/modules/process-compose/module.nix`
- Create: `nix/stackpanel/modules/process-compose.test.nix`

- [ ] **Step 1: Write the smallest config-level test or fixture for the secrets watcher**

Use `nix/stackpanel/modules/turbo.test.nix` as the pattern and create `nix/stackpanel/modules/process-compose.test.nix` with a focused assertion that verifies a new infra process is emitted only when the watcher is enabled.

- [ ] **Step 2: Add an optional secrets/env watcher process**

Implementation notes:

- Extend `nix/stackpanel/modules/process-compose/module.nix` with a `secretsWatcher` infra process, modeled after `format-watch`.
- Keep it narrow: watch only secrets/env-codegen-relevant files at first.
- Use `watchexec` to run `stackpanel preflight run env --quiet`.
- Put it in the `infra` namespace, default it to enabled only when env/secrets codegen is configured, and make it optional/configurable.
- This watcher is additive: it improves live updates during `dev`, but shell entry must remain correct when `dev` is not running.

- [ ] **Step 3: Verify the watcher appears in process-compose config**

Run:

```bash
nix develop --impure -c bash -lc 'python - <<"PY"
import pathlib
path = pathlib.Path("process-compose.yaml")
print(path.resolve())
print(path.read_text())
PY' | grep -n "secrets-watch"
```

Expected: a `secrets-watch` infra process is present when enabled

- [ ] **Step 4: Verify the watcher refreshes env artifacts during `dev`**

Run a local manual check:

```bash
dev &
# change one watched secret/env source file
git diff -- packages/gen/env
```

Expected: the watcher updates the affected env artifacts without needing a new shell entry

- [ ] **Step 5: Commit**

```bash
git add nix/stackpanel/modules/process-compose/module.nix nix/stackpanel/modules/process-compose.test.nix
git commit -m "feat: watch secrets codegen during dev"
```

## Task 6: Full Verification Against the Spec

**Files:**
- Modify as needed from prior tasks only

- [ ] **Step 1: Run the focused Go tests**

Run:

```bash
cd apps/stackpanel-go && go test ./pkg/runtimepaths ./internal/codegen ./cmd/cli -count=1
```

Expected: PASS

- [ ] **Step 2: Verify the flake archive path stays stable across shell entry**

Run:

```bash
python - <<'PY'
import json, subprocess
def archive_path():
    out = subprocess.check_output(['nix', 'flake', 'archive', '--json', '.'], text=True)
    return json.loads(out)['path']
before = archive_path()
subprocess.run(['nix', 'develop', '--impure', '-c', 'true'], check=False)
after = archive_path()
print('before=', before)
print('after =', after)
print('stable=', before == after)
PY
```

Expected: `stable=True`

- [ ] **Step 3: Time repeated `nix develop` runs**

Run:

```bash
command time -p nix develop --impure -c which aws
command time -p nix develop --impure -c which aws
```

Expected:

- second run is materially faster than the first
- output path for `aws` is printed both times
- unchanged encrypted secret inputs do not trigger decrypt work on the second run

- [ ] **Step 4: Verify tracked env artifacts stay unchanged on no-op runs**

Run:

```bash
git diff -- packages/gen/env
STACKPANEL_DEBUG=1 nix develop --impure -c true >/tmp/stackpanel-noop.log 2>&1
grep -n "skipped decrypt" /tmp/stackpanel-noop.log
git diff -- packages/gen/env
```

Expected:

- no diff after the second command when encrypted inputs are unchanged
- `/tmp/stackpanel-noop.log` shows the explicit `skipped decrypt ...` note for unchanged targets

- [ ] **Step 5: Verify a real input change still refreshes artifacts**

Run a controlled local test by changing one reversible env source used in the manifest (for example the docs dev `HOSTNAME` value in the decrypted source file), then:

```bash
nix develop --impure -c true
git diff -- packages/gen/env
```

Expected: only the affected checked-in env artifacts refresh

- [ ] **Step 6: Verify a re-encryption-only secret change does not refresh tracked artifacts**

Run a controlled local test that changes only encrypted source bytes or SOPS metadata while preserving the same plaintext, then:

```bash
nix develop --impure -c true
git diff -- packages/gen/env
```

Expected: no diff for checked-in env artifacts, but the runtime cache manifest records the new encrypted-input stamp

- [ ] **Step 7: Record the devenv reference and follow-up note**

Add a short implementation comment or PR note referencing the `cachix/devenv` `cache_dir` / `runtime_dir` split as prior art. Do **not** import the task runner itself in this change.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "fix: stabilize devshell caching across shell entries"
```
