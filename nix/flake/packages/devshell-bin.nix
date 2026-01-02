# ==============================================================================
# devshell-bin.nix
#
# Creates a derivation that contains symlinks to all binaries from the devshell.
# This allows you to reference all devshell tools in a single directory without
# entering the shell.
#
# Usage:
#   nix build .#devshell-bin
#   ./result/bin/go version
#   ./result/bin/air --help
# ==============================================================================
{
  pkgs,
  devShell,
}:
let
  lib = pkgs.lib;

  # Extract all packages from the devshell
  # devShell is expected to be the result of mkDevShell
  devshellConfig = devShell.passthru.devshellConfig or { };
  allPackages = devshellConfig.packages or [ ];
in
pkgs.runCommand "devshell-bin"
  {
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  ''
    mkdir -p $out/bin

    # Create symlinks for all binaries from all packages
    ${lib.concatMapStringsSep "\n" (pkg: ''
      if [ -d "${pkg}/bin" ]; then
        for bin in ${pkg}/bin/*; do
          if [ -f "$bin" ] || [ -L "$bin" ]; then
            binname=$(basename "$bin")
            # Only create symlink if it doesn't already exist
            # (first package wins in case of conflicts)
            if [ ! -e "$out/bin/$binname" ]; then
              ln -s "$bin" "$out/bin/$binname"
            fi
          fi
        done
      fi
    '') allPackages}

    # If no binaries were found, create a marker file
    if [ -z "$(ls -A $out/bin 2>/dev/null)" ]; then
      echo "No binaries found in devshell packages" > $out/bin/.empty
    fi
  ''
