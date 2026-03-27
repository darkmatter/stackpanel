# ==============================================================================
# gc-roots.nix
#
# GC root management with numbered generations.
#
# Prevents `nix-collect-garbage` from removing store paths that the current
# (and recent previous) devshells depend on.  Without this, closing a shell
# and running GC can silently invalidate the cached environment — the next
# shell entry will reference vanished store paths and break.
#
# Inspired by devenv's `.devenv/gc/` directory, which keeps numbered
# generation symlinks:
#
#   .stack/state/gc/
#   ├── profile            -> profile-3-link     (current pointer)
#   ├── profile-1-link     -> /nix/store/…       (old generation)
#   ├── profile-2-link     -> /nix/store/…       (old generation)
#   ├── profile-3-link     -> /nix/store/…       (current generation)
#   ├── hook               -> hook-3-link
#   ├── hook-1-link        -> /nix/store/…-stackpanel-shellhook
#   ├── hook-2-link        -> /nix/store/…-stackpanel-shellhook
#   └── hook-3-link        -> /nix/store/…-stackpanel-shellhook
#
# On every shell entry the module:
#   1. Checks whether the store paths changed since the last generation.
#   2. If yes, creates a new numbered generation and registers it as an
#      indirect GC root via `nix-store --realise --add-root`.
#   3. Prunes generations older than the retention limit.
#
# Retained generations protect against the following scenario:
#   - User exits the shell.
#   - Runs `nix-collect-garbage`.
#   - Re-enters the shell — if the cached env or profile was GC'd the shell
#     would be broken.  With GC roots the last N generations are preserved.
#
# Usage:
#   # Enabled by default (3 generations kept).  To customise:
#   stackpanel.devshell.gc.retain = 5;
#
#   # To disable:
#   stackpanel.devshell.gc.enable = false;
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.devshell.gc;
  profileCfg = config.stackpanel.devshell.profile;
  util = config.stackpanel.util;

  # Known at Nix evaluation time — hardcoded into the script.
  profilePath =
    if profileCfg.enable or false then
      toString profileCfg.package
    else
      "";

  retain = cfg.retain;

  # ── GC root update script ─────────────────────────────────────────────────
  #
  # Runs at shell entry (hooks.after).  Idempotent — only creates a new
  # generation when the store path for a root actually changes.
  #
  gcUpdateScript = pkgs.writeShellScript "stackpanel-gc-update" ''
    set -euo pipefail

    GC_DIR="''${STACKPANEL_STATE_DIR:-.stack/profile}/gc"
    mkdir -p "$GC_DIR"

    RETAIN=${toString retain}

    # ── helpers ────────────────────────────────────────────────────────────

    # Return the current generation number for a named root (0 if none).
    current_gen() {
      local name="$1"
      if [[ -L "$GC_DIR/$name" ]]; then
        local target
        target=$(readlink "$GC_DIR/$name")
        if [[ "$target" =~ ^''${name}-([0-9]+)-link$ ]]; then
          echo "''${BASH_REMATCH[1]}"
          return
        fi
      fi
      echo "0"
    }

    # Resolve the store path a generation link points to (empty if missing).
    resolve_gen() {
      local name="$1" gen="$2"
      local link="$GC_DIR/''${name}-''${gen}-link"
      if [[ -L "$link" ]]; then
        readlink "$link"
      fi
    }

    # Register (or skip) a named GC root.
    #
    # Creates a new generation only when the target store path differs from
    # the current one.  Uses `nix-store --realise --add-root` so that the
    # link is registered as an indirect GC root in
    # /nix/var/nix/gcroots/auto/.
    #
    # Falls back to a plain symlink if nix-store is unavailable (the
    # symlink alone is not a proper GC root but still serves as a signal
    # to human readers and to some nix GC heuristics).
    register_root() {
      local name="$1"
      local store_path="$2"

      # Skip empty / missing paths
      [[ -n "$store_path" ]] || return 0
      [[ -e "$store_path" ]] || return 0

      local cur_gen
      cur_gen=$(current_gen "$name")

      # Check if the current generation already points here — skip if so.
      local cur_target
      cur_target=$(resolve_gen "$name" "$cur_gen")
      if [[ "$cur_target" == "$store_path" ]]; then
        return 0
      fi

      local next_gen=$((cur_gen + 1))
      local link="$GC_DIR/''${name}-''${next_gen}-link"

      # Try proper indirect GC root registration first.
      if nix-store --realise "$store_path" --add-root "$link" > /dev/null 2>&1; then
        : # registered
      else
        # Fallback: plain symlink (best-effort).
        ln -sfn "$store_path" "$link"
      fi

      # Update the "current" pointer (relative symlink within gc/).
      ln -sfn "''${name}-''${next_gen}-link" "$GC_DIR/$name"

      # ── Prune old generations ────────────────────────────────────────
      local cutoff=$((next_gen - RETAIN))
      for old_link in "$GC_DIR"/''${name}-*-link; do
        [[ -L "$old_link" ]] || continue
        local base
        base=$(basename "$old_link")
        if [[ "$base" =~ ^''${name}-([0-9]+)-link$ ]]; then
          local gen_num="''${BASH_REMATCH[1]}"
          if (( gen_num > 0 && gen_num <= cutoff )); then
            rm -f "$old_link"
          fi
        fi
      done
    }

    # ── register all roots ─────────────────────────────────────────────────

    # 1. Profile — contains all devshell package binaries.
    #    Known at Nix evaluation time, hardcoded below.
    PROFILE_PATH="${profilePath}"
    if [[ -n "$PROFILE_PATH" ]]; then
      register_root "profile" "$PROFILE_PATH"
    fi

    # 2. Shell hook — the shellhook.sh derivation.
    #    Discovered at runtime via the env var set by the flake builder.
    if [[ -n "''${STACKPANEL_SHELL_HOOK_PATH:-}" ]]; then
      # STACKPANEL_SHELL_HOOK_PATH points to …/shellhook.sh inside the
      # derivation.  We root the derivation directory itself.
      HOOK_DRV="$(dirname "''${STACKPANEL_SHELL_HOOK_PATH}")"
      register_root "hook" "$HOOK_DRV"
    fi
  '';
in
{
  # ── Options ────────────────────────────────────────────────────────────────
  options.stackpanel.devshell.gc = {
    enable =
      lib.mkEnableOption "GC root management with numbered generations"
      // {
        default = true;
      };

    retain = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Number of shell generations to keep as GC roots.

        When a new generation is created (because the profile or shellhook
        store path changed), generations older than this limit are pruned.
        Keeping a few old generations protects against the following sequence:

          1. User rebuilds the shell (new store paths).
          2. Runs `nix-collect-garbage`.
          3. Tries to re-enter the *previous* shell (e.g. stale direnv cache)
             — the old store paths are still alive.

        Higher values use more disk space but provide a wider safety net.
      '';
      example = 5;
    };
  };

  # ── Config ─────────────────────────────────────────────────────────────────
  config = lib.mkIf (config.stackpanel.enable && cfg.enable) {
    # Run after profile and shellhook symlinks have been created.
    stackpanel.devshell.hooks.after = [
      ''
        ${util.log.debug "gc: updating GC roots (retain=${toString retain})"}
        ${gcUpdateScript}
      ''
    ];
  };
}
