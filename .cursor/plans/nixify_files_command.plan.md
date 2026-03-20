---
name: "stack nixify — Progressive File Nixification"
overview: |
  Files like process-compose.yml, .vscode/settings.json, and .tasks/bin/*
  contain store paths or user-specific paths. They need to exist on disk for
  tools to consume, but their content is derived from Nix configuration.

  Today these files are written to disk and tracked in git, even though their
  built state contains machine-specific store paths that pollute commits.
  The long-term goal is for the Nix module to BE the source of truth, with
  the tool-specific file generated as an artifact (gitignored, materialized
  on shell entry by write-files).

  `stack nixify <file>` bridges the gap. It converts a git-tracked
  configuration file into a Nix-generated one, so users can progressively
  adopt the pure-Nix approach when they're ready.

  ## Scope

  nixify targets **configuration and generated files** — IDE settings, process
  managers, task scripts, gitignore, linter configs, etc. It does NOT handle
  package/dependency management (package.json, go.mod, Cargo.lock). For those,
  users should use dedicated tools: bun2nix, gomod2nix, cargo2nix, etc.

  Stack's promise is: if removed, the right files are still in the right
  place. So both modes must coexist. Tracked files stay in git. Gitignored
  files are generated from Nix. The nixify command moves files from the
  former to the latter.

design: |
  ## Write Behavior: Derivations vs Regular Files

  Understanding how files.entries types map to disk:

  | Type | On disk | Contains store paths? | Safe to git-track? |
  |------|---------|----------------------|-------------------|
  | text, json, line-set, line-map | Regular file (copy) | Maybe (if Nix interpolations reference store) | Yes, but noisy diffs |
  | derivation | Regular file (copy from drv outPath) | Usually yes | Yes, but noisy diffs |
  | symlink | Symlink → /nix/store/... | Target IS a store path | **No** — broken on other machines |

  Key insight: `type = "derivation"` creates a **copy**, not a symlink.
  Symlinks to store paths must never be git-tracked — they're meaningless
  on other machines. Derivation copies CAN be tracked but contain
  machine-specific store paths.

  ## File Modes: `gitignored`

  Each files.entries definition has a `gitignored` flag:

  ```nix
  stack.files.entries.".vscode/settings.json" = {
    type = "json";
    gitignored = true;    # → added to .gitignore, regenerated on shell entry
    # gitignored = false;  # → tracked in git, --skip-worktree for store paths (default)
    jsonValue = { ... };
  };
  ```

  ### `gitignored = false` (default)
  - File is written to disk as a regular file by write-files
  - File is tracked in git (removing stack leaves it intact)
  - If file contains store paths, `git update-index --skip-worktree` is
    applied automatically to hide store-path churn from `git status`
  - Store paths in the file make cross-machine git diffs noisy

  ### `gitignored = true`
  - Nix module is the source of truth (the .nix file is in git)
  - Tool-specific file is generated and written to disk on shell entry
  - File path is automatically added to `.gitignore` (via line-set merge)
  - write-files runs `git rm --cached` if the file was previously tracked
  - Removing stack removes the generated file (but the .nix source remains)
  - No store paths in git, deterministic from flake inputs

  ### `type = "symlink"` implies `gitignored = true`
  - Symlinks to store paths are always gitignored (they'd be broken on
    other machines). The `gitignored` flag is forced to true for symlinks.

  ## The `nixify` Command

  ```
  stack nixify <file>              # Convert a file to gitignored Nix
  stack nixify --list              # Show which files are nixifiable
  stack nixify --status            # Show tracked vs gitignored status
  stack nixify --revert <file>     # Convert back to tracked
  ```

  ### What `nixify <file>` does

  1. **Detect file type** — JSON, YAML, TOML, plain text, shell script
  2. **Parse content** — Read current on-disk file
  3. **Generate Nix expression** — Convert to a `files.entries` definition:
     - JSON → `type = "json"; jsonValue = { ... };`
     - Line-based (gitignore, env) → `type = "line-set"; lines = [ ... ];`
     - Shell scripts → `type = "derivation"; drv = pkgs.writeScript ...;`
     - YAML/TOML → `type = "text"; text = lib.generators.toYAML {} { ... };`
  4. **Write Nix module** — Create `.stack/modules/<name>.nix` with the entry
  5. **Set `gitignored = true`** — File is added to `.gitignore` automatically
  6. **Remove from git** — `git rm --cached <file>` (keeps on disk, removes from index)

  ### Detection of nixifiable files

  Files managed by `stack.files.entries` that have `gitignored = false`
  are candidates. The `--list` command shows these with a hint about what the
  Nix module would look like.

  ### Store path replacement

  The key value of nixify is replacing hardcoded store paths with Nix
  expressions. For example:

  ```json
  // Tracked .vscode/settings.json (in git, noisy diffs)
  { "nix.serverPath": "/nix/store/abc123-nixd-2.0/bin/nixd" }

  // After nixify → .stack/modules/vscode-settings.nix (in git, clean)
  stack.files.entries.".vscode/settings.json" = {
    type = "json";
    gitignored = true;
    jsonValue = {
      "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
    };
  };
  ```

  The nixify command can attempt to reverse-resolve store paths back to
  package references using `nix-store --query --deriver` or by matching
  against known packages in the devshell.

  ## Skip-Worktree Integration (Tracked Mode)

  For files that remain tracked (`gitignored = false`), reduce git noise
  with `--skip-worktree`. The write-files script automatically runs this
  after writing a tracked file that contains store paths:

  ```bash
  # After writing a tracked file with store paths
  if git ls-files --error-unmatch "$file" &>/dev/null; then
    git update-index --skip-worktree "$file"
  fi
  ```

  This is transparent — the file exists in git (stack removal is safe)
  but local changes from store path updates don't pollute `git status`.

  A `stack unskip` command (or `--no-skip-worktree` flag) can undo this
  when the user wants to commit intentional changes.

  ## Progressive Migration Path

  1. **Day 0**: All files have `gitignored = false` (current behavior)
  2. **User runs `stack nixify .vscode/settings.json`**:
     - Generates `.stack/modules/vscode-settings.nix`
     - Sets `gitignored = true` on the entry
     - Removes file from git index, added to `.gitignore`
  3. **User sees cleaner git history**, tries more files
  4. **Eventually**: Most generated files are gitignored, git history is clean

  ## File Type Handlers

  The nixify command handles **configuration and generated files only** — not
  package manifests or lockfiles. For dependency management, use dedicated
  tools (bun2nix, gomod2nix, cargo2nix, poetry2nix, etc.).

  Supported formats:

  | Format | Parse | Generate Nix |
  |--------|-------|-------------|
  | JSON | `builtins.fromJSON` | `type = "json"; jsonValue = ...;` |
  | YAML | Go yaml parser | `type = "text"; text = lib.generators.toYAML {} ...;` |
  | TOML | Go toml parser | `type = "text"; text = lib.generators.toTOML {} ...;` |
  | .env | line split on `=` | `type = "line-set"; lines = [...];` |
  | gitignore | line split | `type = "line-set"; lines = [...];` |
  | Shell script | identity | `type = "derivation"; drv = pkgs.writeScript ...;` |
  | Anything else | identity | `type = "text"; text = ''...'';` |

  Out of scope (use dedicated tools instead):

  | File | Tool |
  |------|------|
  | package.json / bun.lock | bun2nix |
  | go.mod / go.sum | gomod2nix |
  | Cargo.toml / Cargo.lock | cargo2nix, crane, naersk |
  | pyproject.toml / poetry.lock | poetry2nix, uv2nix |

  All generated entries get `gitignored = true` by default since the Nix
  module is now the source of truth.

  ## Store Path Reverse Resolution

  The hardest part of nixify is replacing `/nix/store/xxx-pkg/bin/foo` with
  `${pkgs.pkg}/bin/foo`. Strategies:

  1. **Devshell package matching** — Compare store paths against packages in
     the current devshell. Most store paths come from devshell packages.
  2. **`nix-store -q --deriver`** — Get the derivation that produced a path,
     extract the package name.
  3. **Known patterns** — Match common paths like `${pkgs.nixd}/bin/nixd`,
     `${pkgs.go}/bin/go`, etc. from a registry of well-known tools.
  4. **Fallback** — Leave unresolvable store paths as string literals with a
     TODO comment: `# TODO: replace with package reference`.

todos:
  - id: gitignored-flag
    content: |
      Add `gitignored` option to files.entries submodule (bool, default false).
      When true, auto-append file path to .gitignore line-set entry and run
      `git rm --cached` in write-files if the file is currently tracked.
      Force `gitignored = true` for `type = "symlink"` entries (symlinks to
      store paths are meaningless in git on other machines).
    status: pending

  - id: skip-worktree
    content: |
      In write-files, after writing a tracked (`gitignored = false`) file
      that contains store paths (/nix/store/), automatically apply
      `git update-index --skip-worktree` to reduce git noise. Add a
      `stack unskip [file]` command to undo this when the user wants
      to commit intentional changes.
    status: pending
    dependencies:
      - gitignored-flag

  - id: cli-nixify-scaffold
    content: |
      Add `stack nixify` subcommand to the Go CLI. Start with JSON files
      since builtins.fromJSON handles parsing. Read file, detect type, generate
      a .stack/modules/<name>.nix with the appropriate files.entries def.
      All generated entries default to `gitignored = true`.
    status: pending
    dependencies:
      - gitignored-flag

  - id: store-path-resolver
    content: |
      Implement store path reverse resolution. Given a store path, try to map
      it back to a `pkgs.X` reference. Strategies in priority order:
        1. Match against serialized devshell packages in state
        2. `nix-store --query --deriver` to get derivation name
        3. Known-tools registry (nixd, go, bun, etc.)
        4. Fallback: leave as string literal with a TODO comment
    status: pending

  - id: cli-nixify-json
    content: |
      Implement nixify for JSON files (.vscode/settings.json, tsconfig.json,
      etc.). Parse JSON, replace store paths with Nix interpolations, generate
      `type = "json"; gitignored = true; jsonValue = { ... };` entry.
    status: pending
    dependencies:
      - cli-nixify-scaffold
      - store-path-resolver

  - id: cli-nixify-yaml
    content: |
      Implement nixify for YAML files (process-compose.yml, docker-compose.yml).
      Parse YAML in Go, convert to Nix attrset, generate entry using
      lib.generators.toYAML.
    status: pending
    dependencies:
      - cli-nixify-scaffold
      - store-path-resolver

  - id: cli-nixify-scripts
    content: |
      Implement nixify for shell scripts (.tasks/bin/*). Detect shebang,
      replace store paths in command references, generate
      `type = "derivation"; gitignored = true; drv = pkgs.writeScript ...;`
      entry.
    status: pending
    dependencies:
      - cli-nixify-scaffold
      - store-path-resolver

  - id: cli-nixify-lines
    content: |
      Implement nixify for line-based files (.gitignore, .prettierignore,
      .env). Split lines, generate
      `type = "line-set"; gitignored = true; lines = [...];` entry.
    status: pending
    dependencies:
      - cli-nixify-scaffold

  - id: cli-nixify-list
    content: |
      Implement `stack nixify --list` showing files managed by
      files.entries that have `gitignored = false`. Show a preview of
      what the Nix module would look like.
    status: pending
    dependencies:
      - gitignored-flag

  - id: cli-nixify-status
    content: |
      Implement `stack nixify --status` showing a table of all managed
      files with their mode (tracked/gitignored), whether they contain
      store paths, and skip-worktree status.
    status: pending
    dependencies:
      - gitignored-flag
      - skip-worktree

  - id: cli-nixify-revert
    content: |
      Implement `stack nixify --revert <file>` to convert a gitignored
      file back to tracked. Set `gitignored = false`, `git add` the file,
      remove from .gitignore line-set.
    status: pending
    dependencies:
      - cli-nixify-json

  - id: docs
    content: |
      Document the tracked vs gitignored file modes, the nixify command,
      and the progressive migration path. Add to stack docs site.
    status: pending
    dependencies:
      - cli-nixify-json
      - cli-nixify-yaml
      - cli-nixify-scripts
---