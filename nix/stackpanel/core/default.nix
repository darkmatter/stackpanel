# ==============================================================================
# default.nix
#
# Main entry point for the Stackpanel core module.
#
# This module initializes the Stackpanel development environment by:
#   - Importing all option modules from ./options/
#   - Setting up environment variables for root marker and directories
#   - Creating devshell hooks to resolve paths, create directories, and
#     ensure the root marker file and .gitignore entries exist.
#
# Imported by devenv.nix to enable the Stackpanel module system.
# ==============================================================================
{
  config,
  lib,
  ...
}@args:
let
  # Check if pkgs was provided without triggering a lookup error
  hasPkgs = args ? pkgs;
  pkgs = args.pkgs or null;
  cfg = config.stackpanel;
  pathsLib = import ../lib/paths.nix { inherit lib; };
in
{
  imports = [
    ./options
    ./cli.nix
  ];

  config = lib.mkIf cfg.enable {
    # Provide marker + optional root override as data
    stackpanel.devshell.env.STACKPANEL_ROOT_MARKER = cfg.root-marker;
    stackpanel.devshell.env.STACKPANEL_ROOT_DIR_NAME = cfg.dirs.home;

    # If user provided an absolute root, expose it so stackpanel_find_root fallback works
    stackpanel.devshell.env.STACKPANEL_ROOT = lib.mkDefault (if cfg.root != null then cfg.root else "");

    # Core hook: define funcs, resolve paths, ensure dirs + marker + gitignore
    stackpanel.devshell.hooks.before = lib.mkBefore [
      ''
                set -euo pipefail

                ${pathsLib.mkShellPathUtils {
                  rootDir = cfg.dirs.home;
                  rootMarker = cfg.root-marker;
                  # Hardcoded subdirectory names - these are not configurable
                  stateDir = "state";
                  genDir = "gen";
                }}

                # If stackpanel.root was provided, prefer it; otherwise resolve via marker walking
                if [[ -n "''${STACKPANEL_ROOT:-}" ]]; then
                  stackpanel_resolve_paths "$STACKPANEL_ROOT"
                else
                  stackpanel_resolve_paths
                fi

                mkdir -p "$STACKPANEL_STATE_DIR" "$STACKPANEL_GEN_DIR"

                # Ensure marker exists at repo root
                if [[ ! -f "$STACKPANEL_ROOT/${cfg.root-marker}" ]]; then
                  echo "$STACKPANEL_ROOT" > "$STACKPANEL_ROOT/${cfg.root-marker}"
                fi

                # Ensure .stackpanel/.gitignore exists and ignores state/ and config.local.nix
                _sp_gitignore="$STACKPANEL_ROOT_DIR/.gitignore"
                if [[ ! -f "$_sp_gitignore" ]]; then
                  cat > "$_sp_gitignore" << 'EOF'
        ${cfg.dirs.state}/
        config.local.nix
        EOF
                else
                  if ! grep -q "^${cfg.dirs.state}/$" "$_sp_gitignore" 2>/dev/null; then
                    echo "${cfg.dirs.state}/" >> "$_sp_gitignore"
                  fi
                  if ! grep -q "^config\.local\.nix$" "$_sp_gitignore" 2>/dev/null; then
                    echo "config.local.nix" >> "$_sp_gitignore"
                  fi
                fi

                ${lib.optionalString cfg.gitignore.addProjectMarker ''
                  _root_gitignore="$STACKPANEL_ROOT/.gitignore"
                  if [[ -f "$_root_gitignore" ]]; then
                    if ! grep -q "^${cfg.root-marker}$" "$_root_gitignore" 2>/dev/null; then
                      echo "" >> "$_root_gitignore"
                      echo "# Stackpanel root marker (machine-specific)" >> "$_root_gitignore"
                      echo "${cfg.root-marker}" >> "$_root_gitignore"
                    fi
                  fi
                ''}

                # Restore default interactive shell behavior (disable strict error handling)
                set +euo pipefail
      ''
    ];

    # local overrides
  };
}
