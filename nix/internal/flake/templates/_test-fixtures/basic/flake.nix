# Test Fixture: Basic
# Tests: Core evaluation, basic options, no apps
#
# Usage:
#   nix flake check --override-input stackpanel path:/path/to/stackpanel --no-write-lock-file
{
  description = "Test fixture: basic stackpanel config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Override in CI with: --override-input stackpanel path:/path/to/stackpanel
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.stackpanel.flakeModules.default
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {
        pkgs,
        config,
        lib,
        ...
      }: let
        spConfig = config.legacyPackages.stackpanelFullConfig or {};

        # ── Snapshot: assemble all generated files into a single derivation ──
        storePathsByFile = spConfig.files._storePathsByFile or {};
        snapshot = pkgs.runCommand "files-snapshot" {} (
          ''
            mkdir -p $out
          ''
          + lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              path: storePath:
                lib.optionalString (storePath != null) ''
                  mkdir -p "$out/$(dirname '${path}')"
                  cp ${storePath} "$out/${path}"
                ''
            )
            storePathsByFile
          )
        );
      in {
        packages = {
          inherit snapshot;
        };

        checks =
          {
            # Verify stackpanel evaluates
            stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" {} ''
              echo "Fixture: basic"
              echo "stackpanel.enable: ${
                if spConfig.enable or false
                then "true"
                else "false"
              }"
              touch $out
            '';
          }
          // lib.optionalAttrs (builtins.pathExists ./golden) {
            # Compare generated files against checked-in golden directory
            files-snapshot =
              pkgs.runCommand "files-snapshot-check" {
                nativeBuildInputs = [pkgs.diffutils];
              } ''
                diff -ru ${./golden} ${snapshot} || {
                  echo ""
                  echo "═══════════════════════════════════════════════════════"
                  echo "  Snapshot mismatch!"
                  echo "  Run update-golden.sh to update:"
                  echo "    ./nix/flake/templates/_test-fixtures/update-golden.sh basic"
                  echo "═══════════════════════════════════════════════════════"
                  exit 1
                }
                touch $out
              '';
          };
      };
    };
}
