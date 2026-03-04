# ==============================================================================
# bin.nix
#
# Creates .stack/bin with symlinks to all devshell package binaries.
#
# This provides a stable, predictable location for tools that need to reference
# binaries (e.g., IDE configurations, scripts, CI) without hardcoding Nix store
# paths.
#
# Usage:
#   stackpanel.bin.enable = true;  # default: true
#
# Result:
#   .stack/bin/
#     node -> /nix/store/.../bin/node
#     bun -> /nix/store/.../bin/bun
#     ...
#
# The bin directory is regenerated on each shell entry to stay in sync with
# the current devshell packages.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.bin;
  devshellCfg = config.stackpanel.devshell;

  # Get all packages from devshell
  allPackages = devshellCfg.packages or [ ];

  # Build a list of all bin directories from packages
  # Filter to packages that have a /bin directory
  binDirs = lib.filter (p: builtins.pathExists "${p}/bin") allPackages;
  binDirPaths = map (p: "${p}/bin") binDirs;

  # Create a script that generates symlinks at shell entry
  # This runs at runtime so it can iterate over the actual binaries
  generateBinScript = pkgs.writeShellScript "stackpanel-generate-bin" ''
    set -euo pipefail

    BIN_DIR="''${STACKPANEL_ROOT:-.}/.stack/bin"

    # Clean and recreate bin directory
    rm -rf "$BIN_DIR"
    mkdir -p "$BIN_DIR"

    # Symlink all binaries from package bin directories
    for bindir in ${lib.escapeShellArgs binDirPaths}; do
      if [[ -d "$bindir" ]]; then
        for bin in "$bindir"/*; do
          if [[ -x "$bin" && -f "$bin" ]]; then
            name="$(basename "$bin")"
            # Only create symlink if it doesn't exist (first wins)
            if [[ ! -e "$BIN_DIR/$name" ]]; then
              ln -s "$bin" "$BIN_DIR/$name"
            fi
          fi
        done
      fi
    done

    # Count symlinks created
    count=$(find "$BIN_DIR" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      echo "  → .stack/bin: $count binaries" >&2
    fi
  '';
in
{
  options.stackpanel.bin = {
    enable = lib.mkEnableOption "Generate .stack/bin with package symlinks" // {
      default = true;
    };

    addToPath = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to prepend .stack/bin to PATH.
        Usually not needed since the actual packages are already in PATH.
        Enable this if you want scripts outside the shell to use these paths.
      '';
    };
  };

  config = lib.mkIf (config.stackpanel.enable && cfg.enable && binDirPaths != [ ]) {
    # Run the bin generator script on shell entry
    stackpanel.devshell.hooks.after = [
      "${generateBinScript}"
    ];

    # Optionally add .stack/bin to PATH
    stackpanel.devshell.path.prepend = lib.mkIf cfg.addToPath [
      "$STACKPANEL_ROOT/.stack/bin"
    ];
  };
}
