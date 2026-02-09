# ==============================================================================
# paths.nix
#
# Stackpanel path utilities for consistent path resolution across all modules
# and shell scripts. This is a pure library (no pkgs required).
#
# IMPORTANT: NAMING CONVENTIONS
# -----------------------------
# This library uses SUBDIRECTORY NAMES, not full paths:
#   - rootDir = ".stackpanel"  (the stackpanel home directory)
#   - stateDir = "state"       (subdirectory name, NOT ".stackpanel/state")
#   - genDir = "gen"           (subdirectory name, NOT ".stackpanel/gen")
#
# Full paths are computed as: $root/${rootDir}/${stateDir}
# For example: /path/to/project/.stackpanel/state
#
# If you're getting duplicate path segments like ".stackpanel/.stackpanel/state",
# you're passing a full path where a subdirectory name is expected!
#
# Uses a root marker file pattern (similar to devenv's .devenv-root) to allow
# tools to find the project root from any subdirectory.
#
# Features:
#   - Shell functions for finding project root (stackpanel_find_root)
#   - Path resolution utilities (stackpanel_resolve_paths)
#   - Nix-time path computation helpers (mkPaths)
#   - Gitignore generation for stackpanel directories
#
# Usage in Nix modules:
#   let pathsLib = import ./paths.nix { inherit lib; };
#   in pathsLib.mkShellPathUtils {
#     rootDir = ".stackpanel";    # The home directory
#     stateDir = "state";         # SUBDIRECTORY NAME, not full path!
#     genDir = "gen";             # SUBDIRECTORY NAME, not full path!
#   }
#
# Usage in shell scripts:
#   STACKPANEL_ROOT=$(stackpanel_find_root)
# ==============================================================================
# ==============================================================================
{ lib }:
let
  # Default configuration (can be overridden)
  defaults = {
    rootDir = ".stackpanel";
    rootMarker = ".stackpanel-root";
    stateDir = "state";
    genDir = "gen";
  };

  # Shell function to find project root by looking for root marker
  mkShellFindRoot =
    {
      rootDir ? defaults.rootDir,
      rootMarker ? defaults.rootMarker,
    }:
    ''
      stackpanel_find_root() {
        local dir="$PWD"
        local marker="${rootMarker}"

        # First, try to find the marker file by walking up the directory tree
        while [[ "$dir" != "/" ]]; do
          if [[ -f "$dir/$marker" ]]; then
            cat "$dir/$marker"
            return 0
          fi
          dir="$(dirname "$dir")"
        done

        # Fallback 1: check if STACKPANEL_ROOT is already set
        if [[ -n "''${STACKPANEL_ROOT:-}" ]]; then
          echo "$STACKPANEL_ROOT"
          return 0
        fi

        # Fallback 2: use git repository root if available
        # This handles running `nix develop` from subdirectories before marker exists
        if command -v git >/dev/null 2>&1; then
          local git_root
          git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
          if [[ -n "$git_root" ]]; then
            echo "$git_root"
            return 0
          fi
        fi

        # Fallback 3: look for flake.nix by walking up from PWD
        dir="$PWD"
        while [[ "$dir" != "/" ]]; do
          if [[ -f "$dir/flake.nix" ]]; then
            echo "$dir"
            return 0
          fi
          dir="$(dirname "$dir")"
        done

        echo "Error: Could not find stackpanel root (no $marker, git repo, or flake.nix found)" >&2
        return 1
      }
    '';

  # Shell function to resolve all stackpanel paths
  mkShellResolvePaths =
    {
      rootDir ? defaults.rootDir,
      stateDir ? defaults.stateDir,
      genDir ? defaults.genDir,
      rootMarker ? defaults.rootMarker,
    }:
    ''
      stackpanel_resolve_paths() {
        local root="''${1:-$(stackpanel_find_root)}"
        if [[ -z "$root" ]]; then
          return 1
        fi
        if [[ ! -d "$root" ]]; then
          echo "Error: Resolved stackpanel root is not a directory: $root"
          echo "You may need to run on your stackpanel root dir:"
          echo
          echo "    echo \"\$PWD\" > ${rootMarker}"
          echo
          return 1
        fi
        export STACKPANEL_ROOT="$root"
        export STACKPANEL_ROOT_DIR="$root/${rootDir}"
        export STACKPANEL_STATE_DIR="$root/${rootDir}/${stateDir}"
        export STACKPANEL_GEN_DIR="$root/${rootDir}/${genDir}"
      }
    '';
in
{
  inherit defaults mkShellFindRoot mkShellResolvePaths;

  # Combined shell setup script with all path utilities
  # IMPORTANT: stateDir and genDir must be SUBDIRECTORY NAMES, not full paths!
  mkShellPathUtils =
    cfg:
    let
      rootDir = cfg.rootDir or defaults.rootDir;
      rootMarker = cfg.rootMarker or defaults.rootMarker;
      stateDir = cfg.stateDir or defaults.stateDir;
      genDir = cfg.genDir or defaults.genDir;

      # Validate that stateDir doesn't look like a full path (starts with ".")
      validatedStateDir =
        if lib.hasPrefix "." stateDir && stateDir != "." then
          throw ''
            paths.nix: stateDir should be a subdirectory name (e.g., "state"), not a full path!
            Got: "${stateDir}"
            Expected: just the subdirectory name like "state"
            The full path is computed as: $root/${rootDir}/${stateDir}
          ''
        else
          stateDir;

      # Validate that genDir doesn't look like a full path (starts with ".")
      validatedGenDir =
        if lib.hasPrefix "." genDir && genDir != "." then
          throw ''
            paths.nix: genDir should be a subdirectory name (e.g., "gen"), not a full path!
            Got: "${genDir}"
            Expected: just the subdirectory name like "gen"
            The full path is computed as: $root/${rootDir}/${genDir}
          ''
        else
          genDir;
    in
    ''
      # Stackpanel path utilities
      ${mkShellFindRoot { inherit rootDir rootMarker; }}
      ${mkShellResolvePaths {
        rootDir = rootDir;
        stateDir = validatedStateDir;
        genDir = validatedGenDir;
      }}
    '';

  # ============================================================================
  # NIX-TIME PATH HELPERS
  # Pure functions for computing paths at Nix evaluation time
  # ============================================================================

  # Compute derived paths from config
  mkPaths =
    {
      rootDir ? defaults.rootDir,
      stateDir ? defaults.stateDir,
      genDir ? defaults.genDir,
      configDir ? null,
    }:
    {
      root = rootDir;
      state = "${rootDir}/${stateDir}";
      gen = "${rootDir}/${genDir}";
      config = if configDir != null then toString configDir else null;
    };

  # ============================================================================
  # GITIGNORE HELPERS
  # ============================================================================

  # Generate .gitignore content for the stackpanel root directory
  mkGitignore =
    {
      rootMarker ? defaults.rootMarker,
      stateDir ? defaults.stateDir,
      extraEntries ? [ ],
    }:
    lib.concatStringsSep "\n" (
      [
        "${stateDir}/"
        rootMarker
      ]
      ++ extraEntries
    );
}
