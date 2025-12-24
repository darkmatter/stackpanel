# Stackpanel Path Utilities
#
# Provides consistent path resolution across all modules and shell scripts.
# Uses the root marker file pattern (like devenv's .devenv-root) to allow
# tools to find the project root from any subdirectory.
#
# Usage in Nix modules:
#   let pathsLib = import ./paths.nix { inherit lib; };
#   in pathsLib.shellFindRoot  # Shell script snippet
#
# Usage in shell scripts (via exported function):
#   source <stackpanel-paths-script>
#   STACKPANEL_ROOT=$(stackpanel_find_root)
#
{lib}: let
  # Default configuration (can be overridden)
  defaults = {
    rootDir = ".stackpanel";
    rootMarker = ".stackpanel-root";
    stateDir = "state";
    genDir = "gen";
  };

  # Shell function to find project root by looking for root marker
  mkShellFindRoot = {
    rootDir ? defaults.rootDir,
    rootMarker ? defaults.rootMarker,
  }: ''
    stackpanel_find_root() {
      local dir="$PWD"
      local marker="${rootMarker}"
      while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/$marker" ]]; then
          cat "$dir/$marker"
          return 0
        fi
        dir="$(dirname "$dir")"
      done
      # Fallback: check if STACKPANEL_ROOT is already set
      if [[ -n "$STACKPANEL_ROOT" ]]; then
        echo "$STACKPANEL_ROOT"
        return 0
      fi
      echo "Error: Could not find stackpanel root (no $marker found)" >&2
      return 1
    }
  '';

  # Shell function to resolve all stackpanel paths
  mkShellResolvePaths = {
    rootDir ? defaults.rootDir,
    stateDir ? defaults.stateDir,
    genDir ? defaults.genDir,
  }: ''
    stackpanel_resolve_paths() {
      local root="''${1:-$(stackpanel_find_root)}"
      if [[ -z "$root" ]]; then
        return 1
      fi
      export STACKPANEL_ROOT="$root"
      export STACKPANEL_ROOT_DIR="$root/${rootDir}"
      export STACKPANEL_STATE_DIR="$root/${rootDir}/${stateDir}"
      export STACKPANEL_GEN_DIR="$root/${rootDir}/${genDir}"
    }
  '';

in {
  inherit defaults mkShellFindRoot mkShellResolvePaths;

  # Combined shell setup script with all path utilities
  mkShellPathUtils = cfg: let
    rootDir = cfg.rootDir or defaults.rootDir;
    rootMarker = cfg.rootMarker or defaults.rootMarker;
    stateDir = cfg.stateDir or defaults.stateDir;
    genDir = cfg.genDir or defaults.genDir;
  in ''
    # Stackpanel path utilities
    ${mkShellFindRoot { inherit rootDir rootMarker; }}
    ${mkShellResolvePaths { inherit rootDir stateDir genDir; }}
  '';

  # ============================================================================
  # NIX-TIME PATH HELPERS
  # Pure functions for computing paths at Nix evaluation time
  # ============================================================================

  # Compute derived paths from config
  mkPaths = {
    rootDir ? defaults.rootDir,
    stateDir ? defaults.stateDir,
    genDir ? defaults.genDir,
    configDir ? null,
  }: {
    root = rootDir;
    state = "${rootDir}/${stateDir}";
    gen = "${rootDir}/${genDir}";
    config = if configDir != null then toString configDir else null;
  };

  # ============================================================================
  # GITIGNORE HELPERS
  # ============================================================================

  # Generate .gitignore content for the stackpanel root directory
  mkGitignore = {
    rootMarker ? defaults.rootMarker,
    stateDir ? defaults.stateDir,
    extraEntries ? [],
  }: lib.concatStringsSep "\n" ([
    "${stateDir}/"
    rootMarker
  ] ++ extraEntries);
}
