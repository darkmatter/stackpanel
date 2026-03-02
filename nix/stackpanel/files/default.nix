# ==============================================================================
# files.nix
#
# Derivation-based file generation with hash-check caching.
#
# Each file entry is converted to a Nix store derivation at eval time.
# The writer script compares on-disk content against the store path using
# sha256 hashes, skipping unchanged files. A manifest fast path allows
# the common case (no config changes) to exit after a single hash comparison.
#
# For type="text" files, content can be provided via:
#   - text: Inline text content
#   - path: Path to file (content read at eval time)
#
# For type="json" files, provide a Nix attrset via jsonValue. Multiple
# modules can contribute to the same file and values are deep-merged.
#
# Usage (inline text):
#   stackpanel.files.entries.".github/workflows/ci.yml" = {
#     type = "text";
#     text = "name: CI\n...";
#   };
#
# Usage (path to file):
#   stackpanel.files.entries.".github/workflows/ci.yml" = {
#     type = "text";
#     path = ./.stackpanel/src/files/.github/workflows/ci.yml;
#     description = "CI workflow";
#   };
#
# Usage (derivation):
#   stackpanel.files.entries."scripts/deploy.sh" = {
#     type = "derivation";
#     drv = pkgs.writeScript "deploy" "#!/bin/bash\n...";
#     mode = "0755";
#   };
#
# Usage (JSON - deep-mergeable):
#   stackpanel.files.entries."package.json" = {
#     type = "json";
#     jsonValue = {
#       name = "my-app";
#       scripts.dev = "bun dev";
#     };
#   };
#
# Usage (block-managed - preserves user content):
#   stackpanel.files.entries.".gitignore" = {
#     type = "line-set";
#     managed = "block";    # only manage a marker-delimited block
#     dedupe = true;
#     sort = true;
#     lines = [ "node_modules" ".env" ];
#   };
#
#   This produces a file like:
#     # ... user-written content above ...
#
#     # ── BEGIN stackpanel ──
#     # DO NOT EDIT between these markers — managed by stackpanel
#     .env
#     node_modules
#     # ── END stackpanel ──
#
#   User content outside the markers is never touched. On uninstall,
#   only the managed block is removed (the file is kept if non-empty).
#
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.files;

  # Import util for debug logging
  util = config.stackpanel.util;

  q = lib.escapeShellArg;

  # Filter to only enabled files
  enabledFiles = cfg.entries;

  # Check if there are any files to write (and global enable is true)
  hasFiles = enabledFiles != { };

  fileCount = builtins.length (builtins.attrNames enabledFiles);

  # ── Resolve content ──────────────────────────────────────────────────────
  # Resolve text content from either text, path, or jsonValue
  resolveTextContent =
    path: fileConfig:
    let
      fileType = fileConfig.type or "text";
      hasText = fileConfig.text or null != null;
      hasPath = fileConfig.path or null != null;
    in
    if fileType == "json" then
      builtins.toJSON fileConfig.jsonValue
    else if fileType == "line-set" then
      let
        raw = fileConfig.lines;
        deduped = if fileConfig.dedupe or false then lib.unique raw else raw;
        sorted = if fileConfig.sort or false then lib.sort lib.lessThan deduped else deduped;
      in
      lib.concatStringsSep "\n" sorted + "\n"
    else if fileType == "line-map" then
      lib.concatStringsSep "\n" (lib.attrNames (lib.filterAttrs (_: v: v) fileConfig.mapLines)) + "\n"
    else if hasText && hasPath then
      throw "File '${path}': cannot specify both 'text' and 'path' - use one or the other"
    else if hasPath then
      builtins.readFile fileConfig.path
    else if hasText then
      fileConfig.text
    else
      throw "File '${path}': type 'text' requires either 'text' or 'path' to be set";

  # ── Store path resolution ────────────────────────────────────────────────
  # Convert each entry into a Nix store derivation. This is the single source
  # of truth for file content — the writer script and drift check both use it.
  #
  # For JSON files, the store path contains jq-formatted output so that
  # hash comparisons work correctly (the on-disk file is also jq-formatted).
  mkStorePath =
    path: fileConfig:
    let
      fileType = fileConfig.type or "text";
      baseName = builtins.baseNameOf path;
    in
    if fileType == "text" || fileType == "line-set" || fileType == "line-map" then
      pkgs.writeText baseName (resolveTextContent path fileConfig)
    else if fileType == "json" then
      # Pre-format JSON with jq at build time so the store path content
      # matches what gets written on disk (jq-formatted).
      let
        rawJson = pkgs.writeText "${baseName}.raw" (resolveTextContent path fileConfig);
      in
      pkgs.runCommand baseName { nativeBuildInputs = [ pkgs.jq ]; } ''
        ${pkgs.jq}/bin/jq '.' ${rawJson} > $out
      ''
    else if fileType == "derivation" then
      fileConfig.drv
    else
      null; # symlink doesn't have a store path

  # Attrset of { path = storePath; } for all non-symlink entries
  storePathsByFile = lib.mapAttrs (
    path: fileConfig:
    let
      fileType = fileConfig.type or "text";
    in
    if fileType == "symlink" then null else mkStorePath path fileConfig
  ) enabledFiles;

  # ── Manifest (for state tracking and fast path) ──────────────────────────
  manifestEntries = lib.mapAttrsToList (
    path: fileConfig:
    let
      fileType = fileConfig.type or "text";
      storePath = storePathsByFile.${path};
      # Determine content source for text files
      contentSource =
        if fileType == "text" then
          if fileConfig.path or null != null then
            "path"
          else if fileConfig.text or null != null then
            "inline"
          else
            "unknown"
        else if fileType == "json" then
          "json"
        else if fileType == "derivation" then
          "derivation"
        else if fileType == "symlink" then
          "symlink"
        else
          "unknown";
    in
    {
      inherit path;
      type = fileType;
      managed = fileConfig.managed or "full";
      blockLabel = fileConfig.blockLabel or "stackpanel";
      commentPrefix = fileConfig.commentPrefix or "#";
      mode = fileConfig.mode or null;
      source = fileConfig.source or null;
      description = fileConfig.description or null;
      target = fileConfig.target or null;
      contentSource = contentSource;
      storePath = if storePath != null then builtins.toString storePath else null;
    }
  ) enabledFiles;

  manifestJson = builtins.toJSON {
    version = 2;
    files = manifestEntries;
  };

  # ── Manifest hash (fast path) ───────────────────────────────────────────
  # Compute a single hash from all (path, storePath) pairs. When this hash
  # matches the on-disk manifest hash, we know nothing changed and can skip
  # all individual file checks.
  #
  # We include symlink targets in the hash too so symlink target changes
  # are detected.
  manifestHashInput = lib.concatMapStringsSep "\n" (
    entry:
    let
      value =
        if entry.storePath != null then
          entry.storePath
        else if entry.target or null != null then
          "symlink:${entry.target}"
        else
          "unknown";
    in
    "${entry.path}=${value}"
  ) manifestEntries;

  manifestHash = builtins.hashString "sha256" manifestHashInput;

  # ── Per-file write snippets ──────────────────────────────────────────────
  mkWriteSnippet =
    path: fileConfig:
    let
      mode = fileConfig.mode;
      fileType = fileConfig.type;
      managed = fileConfig.managed;
      storePath = storePathsByFile.${path};
      symlinkTarget = fileConfig.target or null;
      beginMarker = "${fileConfig.commentPrefix} ── BEGIN ${fileConfig.blockLabel} ──";
      endMarker = "${fileConfig.commentPrefix} ── END ${fileConfig.blockLabel} ──";
      noEditNotice = "${fileConfig.commentPrefix} DO NOT EDIT between these markers — managed by stackpanel";
    in
    if fileType == "symlink" then
      # Symlinks are always recreated (cheap operation, no hash check needed)
      ''
        # ${path} (symlink)
        mkdir -p "$(dirname ${q path})"
        if [[ "$FORCE" == "0" ]] && [[ -L ${q path} ]] && [[ "$(readlink ${q path})" == ${q symlinkTarget} ]]; then
          UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
          if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
            echo "  skip ${path} (symlink unchanged)"
          fi
        else
          rm -f ${q path} 2>/dev/null || true
          ln -s ${q symlinkTarget} ${q path}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path} -> ${symlinkTarget}"
        fi
      ''
    else if managed == "block" then
      # Block mode: only manage a marker-delimited section within the file.
      # User content outside the markers is preserved.
      ''
        # ${path} (${fileType}, block-managed)
        _src=${storePath}
        _dst=${q path}
        _begin_marker=${q beginMarker}
        _end_marker=${q endMarker}
        _no_edit=${q noEditNotice}

        # Build the full managed block (markers + content)
        _block_content="$(printf '%s\n%s\n%s%s' "$_begin_marker" "$_no_edit" "$(cat "$_src")" "$_end_marker")"

        mkdir -p "$(dirname "$_dst")"

        if [[ ! -f "$_dst" ]]; then
          # File doesn't exist — create with just the managed block
          printf '%s\n' "$_block_content" > "$_dst"
          ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path} (block, new file)"
        elif ! grep -qF "$_begin_marker" "$_dst"; then
          # File exists but no managed block — append
          # Add a blank line separator if file doesn't end with one
          if [[ -s "$_dst" ]] && [[ "$(tail -c1 "$_dst")" != "" ]]; then
            printf '\n' >> "$_dst"
          fi
          printf '\n%s\n' "$_block_content" >> "$_dst"
          ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path} (block, appended)"
        else
          # File exists with managed block — extract current block and compare
          _current_block=$(${pkgs.gawk}/bin/awk -v begin="$_begin_marker" -v end="$_end_marker" '
            $0 == begin { found=1 }
            found { block = block $0 "\n" }
            $0 == end { found=0 }
            END { printf "%s", block }
          ' "$_dst")

          if [[ "$FORCE" == "0" ]] && [[ "$_current_block" == "$_block_content"$'\n' ]]; then
            UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
            if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
              echo "  skip ${path} (block unchanged)"
            fi
          else
            # Replace block between markers (inclusive) using awk
            ${pkgs.gawk}/bin/awk -v begin="$_begin_marker" -v end="$_end_marker" -v replacement="$_block_content" '
              $0 == begin { skip=1; if (!printed) { print replacement; printed=1 }; next }
              skip && $0 == end { skip=0; next }
              !skip { print }
            ' "$_dst" > "$_dst.sp-tmp" && mv "$_dst.sp-tmp" "$_dst"
            ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
            WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
            echo "  write ${path} (block, updated)"
          fi
        fi
      ''
    else
      # Full mode (default): hash-check before writing entire file
      ''
        # ${path} (${fileType})
        _src=${storePath}
        _dst=${q path}
        if [[ "$FORCE" == "0" ]] && [[ -f "$_dst" ]] && [[ "$(${pkgs.coreutils}/bin/sha256sum "$_dst" | cut -d' ' -f1)" == "$(${pkgs.coreutils}/bin/sha256sum "$_src" | cut -d' ' -f1)" ]]; then
          UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
          if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
            echo "  skip ${path} (unchanged)"
          fi
        else
          mkdir -p "$(dirname "$_dst")"
          cat "$_src" > "$_dst"
          ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path}"
        fi
      '';

  # JSON array of all current file paths (for the cleanup diff)
  currentPathsJson = builtins.toJSON (builtins.attrNames enabledFiles);

  # ── Writer script ────────────────────────────────────────────────────────
  writerDrv = pkgs.writeShellApplication {
    name = "write-files";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.gawk
    ];
    text = ''
      set -euo pipefail

      # ── Parse flags ──────────────────────────────────────────────────────
      FORCE=0
      VERBOSE=0
      for arg in "$@"; do
        case "$arg" in
          --force|-f) FORCE=1 ;;
          --verbose|-v) VERBOSE=1 ;;
          --help|-h)
            echo "Usage: write-files [--force] [--verbose]"
            echo "  --force   Skip hash checks, rewrite all files"
            echo "  --verbose Show per-file skip/write details"
            exit 0
            ;;
        esac
      done

      # Determine repo root
      ROOT="''${STACKPANEL_ROOT:-}"
      if [[ -z "$ROOT" ]]; then
        echo "ERROR: STACKPANEL_ROOT is not set. (Stackpanel core should set it.)" >&2
        exit 1
      fi

      cd "$ROOT"

      STATE_DIR="''${STACKPANEL_STATE_DIR:-$ROOT/.stackpanel/state}"
      MANIFEST_FILE="$STATE_DIR/.files-manifest"

      # ── Manifest fast path ──────────────────────────────────────────────
      # If the manifest hash matches, nothing changed — skip everything.
      MANIFEST_HASH="${manifestHash}"
      if [[ "$FORCE" == "0" ]] && [[ -f "$MANIFEST_FILE" ]] && [[ "$(cat "$MANIFEST_FILE")" == "$MANIFEST_HASH" ]]; then
        if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
          echo "files: all ${toString fileCount} files unchanged (skipping)"
        fi
        exit 0
      fi

      # ── Cleanup stale files from previous generation ─────────────────────
      OLD_MANIFEST="$STATE_DIR/files.json"
      REMOVED_COUNT=0
      if [[ -f "$OLD_MANIFEST" ]]; then
        CURRENT_PATHS='${currentPathsJson}'

        # Extract old file entries from the manifest (path + managed mode + markers)
        OLD_ENTRIES=$(jq -r '.files[] | "\(.path)\t\(.managed // "full")\t\(.commentPrefix // "#")\t\(.blockLabel // "stackpanel")"' "$OLD_MANIFEST" 2>/dev/null) || OLD_ENTRIES=""

        while IFS=$'\t' read -r old_path old_managed old_comment_prefix old_block_label; do
          [[ -z "$old_path" ]] && continue
          # Check if this path is still in the current file set
          if ! echo "$CURRENT_PATHS" | jq -e --arg p "$old_path" 'index($p) != null' >/dev/null 2>&1; then
            # This file is stale
            if [[ "$old_managed" == "block" ]]; then
              # Block-managed: strip the managed block instead of deleting
              if [[ -f "$old_path" ]]; then
                _begin="$old_comment_prefix ── BEGIN $old_block_label ──"
                _end="$old_comment_prefix ── END $old_block_label ──"
                if grep -qF "$_begin" "$old_path"; then
                  # Remove the block (and any single blank line immediately before it)
                  ${pkgs.gawk}/bin/awk -v begin="$_begin" -v end="$_end" '
                    $0 == begin { skip=1; if (prev_blank) { prev_blank=0 }; next }
                    skip && $0 == end { skip=0; next }
                    skip { next }
                    /^[[:space:]]*$/ { prev_blank=1; prev_line=$0; next }
                    { if (prev_blank) { print prev_line; prev_blank=0 }; print }
                    END { if (prev_blank) print prev_line }
                  ' "$old_path" > "$old_path.sp-tmp" && mv "$old_path.sp-tmp" "$old_path"
                  echo "  remove $old_path (stale block stripped)"
                  REMOVED_COUNT=$((REMOVED_COUNT + 1))
                  # If the file is now empty (or only whitespace), remove it
                  if [[ ! -s "$old_path" ]] || ! grep -q '[^[:space:]]' "$old_path"; then
                    rm -f "$old_path"
                    echo "  remove $old_path (empty after block removal)"
                  fi
                fi
              fi
            else
              # Full-managed: delete the entire file
              if [[ -e "$old_path" || -L "$old_path" ]]; then
                rm -f "$old_path" 2>/dev/null || true
                echo "  remove $old_path (stale)"
                REMOVED_COUNT=$((REMOVED_COUNT + 1))

                # Clean up empty parent directories (up to repo root)
                dir=$(dirname "$old_path")
                while [[ "$dir" != "." && "$dir" != "/" ]]; do
                  if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                    rmdir "$dir" 2>/dev/null || true
                  else
                    break
                  fi
                  dir=$(dirname "$dir")
                done
              fi
            fi
          fi
        done <<< "$OLD_ENTRIES"
      fi

      # ── Write current files (with hash check) ───────────────────────────
      WRITTEN_COUNT=0
      UNCHANGED_COUNT=0

      ${lib.concatLines (lib.mapAttrsToList mkWriteSnippet enabledFiles)}

      # ── Write manifest ──────────────────────────────────────────────────
      mkdir -p "$STATE_DIR"
      cat > "$STATE_DIR/files.json" << 'STACKPANEL_FILES_EOF'
      ${manifestJson}
      STACKPANEL_FILES_EOF

      # Write manifest hash for fast path on next run
      echo -n "$MANIFEST_HASH" > "$MANIFEST_FILE"

      # ── Summary ─────────────────────────────────────────────────────────
      PARTS=""
      if [[ "$WRITTEN_COUNT" -gt 0 ]]; then
        PARTS="$WRITTEN_COUNT written"
      fi
      if [[ "$UNCHANGED_COUNT" -gt 0 ]]; then
        if [[ -n "$PARTS" ]]; then PARTS="$PARTS, "; fi
        PARTS="''${PARTS}$UNCHANGED_COUNT unchanged"
      fi
      if [[ "$REMOVED_COUNT" -gt 0 ]]; then
        if [[ -n "$PARTS" ]]; then PARTS="$PARTS, "; fi
        PARTS="''${PARTS}$REMOVED_COUNT removed"
      fi
      echo "files: $PARTS"
    '';
  };

  # ── Drift check derivation ──────────────────────────────────────────────
  # A derivation that verifies on-disk files match their expected store content.
  # Used via `nix flake check` or exposed as a moduleCheck.
  #
  # NOTE: This check requires IFD (import-from-derivation) or must be run
  # against a checkout. We build it as a script that takes ROOT as an argument.
  driftCheckScript =
    let
      # Only check files that have a store path (skip symlinks)
      checkableFiles = lib.filterAttrs (_: v: v != null) storePathsByFile;

      # Full-managed files: compare entire file hash
      fullManagedFiles = lib.filterAttrs (
        path: _: (enabledFiles.${path}.managed or "full") == "full"
      ) checkableFiles;
      fullCheckSnippets = lib.mapAttrsToList (path: storePath: ''
        _dst="$ROOT/${path}"
        if [[ ! -f "$_dst" ]]; then
          echo "DRIFT: ${path} is missing (expected from store)"
          DRIFT=1
        else
          _expected=$(${pkgs.coreutils}/bin/sha256sum ${storePath} | cut -d' ' -f1)
          _actual=$(${pkgs.coreutils}/bin/sha256sum "$_dst" | cut -d' ' -f1)
          if [[ "$_expected" != "$_actual" ]]; then
            echo "DRIFT: ${path} does not match generated content"
            DRIFT=1
          fi
        fi
      '') fullManagedFiles;

      # Block-managed files: extract the block and compare against expected content
      blockManagedFiles = lib.filterAttrs (
        path: _: (enabledFiles.${path}.managed or "full") == "block"
      ) checkableFiles;
      blockCheckSnippets = lib.mapAttrsToList (
        path: storePath:
        let
          fc = enabledFiles.${path};
          beginMarker = "${fc.commentPrefix} ── BEGIN ${fc.blockLabel} ──";
          endMarker = "${fc.commentPrefix} ── END ${fc.blockLabel} ──";
          noEditNotice = "${fc.commentPrefix} DO NOT EDIT between these markers — managed by stackpanel";
        in
        ''
          _dst="$ROOT/${path}"
          if [[ ! -f "$_dst" ]]; then
            echo "DRIFT: ${path} is missing (expected block-managed file)"
            DRIFT=1
          elif ! grep -qF ${q beginMarker} "$_dst"; then
            echo "DRIFT: ${path} is missing managed block (expected ${q beginMarker})"
            DRIFT=1
          else
            # Extract the content between markers (excluding markers and notice line)
            _block_content=$(${pkgs.gawk}/bin/awk -v begin=${q beginMarker} -v end=${q endMarker} -v notice=${q noEditNotice} '
              $0 == begin { found=1; next }
              found && $0 == notice { next }
              found && $0 == end { found=0; next }
              found { print }
            ' "$_dst")
            _expected=$(cat ${storePath})
            if [[ "$_block_content" != "$_expected" ]]; then
              echo "DRIFT: ${path} managed block does not match expected content"
              DRIFT=1
            fi
          fi
        ''
      ) blockManagedFiles;

      # Also check symlinks
      symlinkFiles = lib.filterAttrs (_: fc: (fc.type or "text") == "symlink") enabledFiles;
      symlinkSnippets = lib.mapAttrsToList (path: fileConfig: ''
        _dst="$ROOT/${path}"
        if [[ ! -L "$_dst" ]]; then
          echo "DRIFT: ${path} is not a symlink (expected -> ${fileConfig.target})"
          DRIFT=1
        elif [[ "$(readlink "$_dst")" != ${q fileConfig.target} ]]; then
          echo "DRIFT: ${path} points to $(readlink "$_dst"), expected ${fileConfig.target}"
          DRIFT=1
        fi
      '') symlinkFiles;
    in
    pkgs.writeShellApplication {
      name = "check-files-drift";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
      ];
      text = ''
        set -euo pipefail

        ROOT="''${1:-''${STACKPANEL_ROOT:-}}"
        if [[ -z "$ROOT" ]]; then
          echo "Usage: check-files-drift [ROOT]" >&2
          echo "  or set STACKPANEL_ROOT" >&2
          exit 1
        fi

        cd "$ROOT"
        DRIFT=0

        ${lib.concatLines fullCheckSnippets}
        ${lib.concatLines blockCheckSnippets}
        ${lib.concatLines symlinkSnippets}

        if [[ "$DRIFT" == "1" ]]; then
          echo ""
          echo "Some generated files are out of date."
          echo "Run 'write-files' to fix."
          exit 1
        else
          echo "All ${toString fileCount} generated files are up to date."
        fi
      '';
    };
in
{
  options.stackpanel.files = {
    enable = lib.mkEnableOption "file generation" // {
      default = true;
    };

    entries = lib.mkOption {
      description = ''
        Files to generate into the repo. Keys are file paths relative to repo root.

        Supported types:
          - text: Inline text content (via `text` or `path`)
          - json: Nix attrset serialized to formatted JSON (deep-mergeable)
          - line-set: List of strings joined by newlines (with optional `dedupe`/`sort`)
          - line-map: Attrset where truthy keys become lines (allows override/disable)
          - derivation: Copy from a Nix derivation
          - symlink: Create a symbolic link
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              enable = lib.mkEnableOption "Generate this file" // {
                default = true;
              };

              type = lib.mkOption {
                type = lib.types.enum [
                  "text"
                  "derivation"
                  "symlink"
                  "json"
                  "line-set"
                  "line-map"
                ];
                default = "text";
                description = ''
                  Type of file content:
                  - 'text': inline text content
                  - 'derivation': copy from a derivation
                  - 'symlink': create a symbolic link
                  - 'json': Nix value serialized to formatted JSON (supports deep merge from multiple modules)
                  - 'line-set': list of strings joined by newlines (with optional dedupe/sort)
                  - 'line-map': attrset where each key with a truthy value becomes a line (allows override/disable across modules)
                '';
              };

              text = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Text content for the file (when type = 'text').
                  Mutually exclusive with `path` - use one or the other.
                '';
              };

              jsonValue = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
                description = "Nix attrset to serialize as formatted JSON (when type = 'json'). Deep-merged across modules.";
              };

              lines = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "List of lines (when type = 'line-set'). Merged across modules via list concatenation.";
              };

              dedupe = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Remove duplicate lines from the output (when type = 'line-set').";
              };

              sort = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Sort lines alphabetically in the output (when type = 'line-set').";
              };

              mapLines = lib.mkOption {
                type = lib.types.attrsOf lib.types.bool;
                default = { };
                description = "Attrset of lines (when type = 'line-map'). Keys with true become lines; false excludes them.";
              };

              path = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to file content (when type = 'text'). Read at eval time. Mutually exclusive with `text`.";
              };

              drv = lib.mkOption {
                type = lib.types.nullOr lib.types.package;
                default = null;
                description = "Derivation whose outPath contains the file content (when type = 'derivation').";
              };

              target = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Symlink target path (when type = 'symlink'). Can be absolute (Nix store) or relative.";
              };

              managed = lib.mkOption {
                type = lib.types.enum [
                  "full"
                  "block"
                ];
                default = "full";
                description = ''
                  How the file is managed:
                  - 'full': the entire file is owned by stackpanel (default). The file is
                    overwritten on write and deleted when stale.
                  - 'block': only a marker-delimited block within the file is managed.
                    Content outside the block is preserved. On uninstall, only the block
                    is removed (the file itself is kept unless empty). This is useful for
                    files like .gitignore where user content must coexist with managed content.
                '';
              };

              blockLabel = lib.mkOption {
                type = lib.types.str;
                default = "stackpanel";
                description = ''
                  Label used in the BEGIN/END markers for block-managed files.
                  The markers will be: "# ── BEGIN <label> ──" / "# ── END <label> ──"
                  Only used when managed = "block".
                '';
              };

              commentPrefix = lib.mkOption {
                type = lib.types.str;
                default = "#";
                description = ''
                  Comment prefix for block markers. Defaults to "#" which works for
                  gitignore, shell scripts, YAML, TOML, etc. Set to "//" for JSON-like,
                  or ";" for INI files, etc. Only used when managed = "block".
                '';
              };

              mode = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional chmod mode (e.g. '0644', '0755').";
              };

              source = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Module or component that generated this file (for UI display).";
              };

              description = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Human-readable description of the file's purpose.";
              };
            };
          }
        )
      );
      default = { };
    };
  };

  config = lib.mkIf hasFiles {
    # Make the executable available in PATH
    stackpanel.devshell.packages = [
      writerDrv
      driftCheckScript
    ];

    # Run write-files on shell entry (after core setup which sets STACKPANEL_ROOT)
    stackpanel.devshell.hooks.main = [
      ''
        ${util.log.debug "files: invoking write-files on shell entry"}
        ${writerDrv}/bin/write-files
      ''
    ];

    # Also expose as stackpanel scripts
    stackpanel.scripts."write-files" = {
      exec = ''${writerDrv}/bin/write-files "$@"'';
      description = "Write generated files to the project (with hash-check caching)";
      turbo = {
        enable = true;
        cache = false;
        inputs = [
          ".stackpanel/**"
          "nix/stackpanel/**"
        ];
      };
    };

    stackpanel.scripts."check-files" = {
      exec = ''${driftCheckScript}/bin/check-files-drift "$@"'';
      description = "Check if generated files are up-to-date (drift detection)";
      turbo = {
        enable = true;
        cache = false;
        dependsOn = [ "write-files" ];
        inputs = [
          ".stackpanel/**"
          "nix/stackpanel/**"
        ];
      };
    };
  };
}
