# Test Fixture: Basic
# Tests: Core evaluation, basic options, no apps
#
# Usage:
#   nix flake check --override-input stackpanel path:/path/to/stackpanel --no-write-lock-file
{
  description = "Test fixture: basic stackpanel config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Override in CI with: --override-input stackpanel path:/path/to/stackpanel
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";

    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    stackpanel,
    ...
  } @ inputs:
  # Use stackpanel.lib.mkFlake for core outputs
    stackpanel.lib.mkFlake {inherit inputs self;}
    # Add test-specific checks
    // flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = stackpanel.lib.requiredOverlays;
        };
        lib = pkgs.lib;
        spOutputs = stackpanel.lib.mkOutputs {
          inherit pkgs inputs self system;
        };
        spConfig = spOutputs.legacyPackages.stackpanelFullConfig or {};

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
                  echo "  Run update-golden.sh to update: "
                  echo "    ./nix/flake/templates/_test-fixtures/update-golden.sh basic"
                  echo "═══════════════════════════════════════════════════════"
                  exit 1
                }
                touch $out
              '';
          };
      }
    );
}
