# Test Fixture: Basic
# Tests: Core evaluation, basic options, no apps
{
  description = "Test fixture: basic stackpanel config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Override in CI with: --override-input stackpanel git+file:/path/to/stackpanel
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
  };

  outputs =
    { self, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake {
      inherit inputs self;

      perSystem =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          spConfig = config.legacyPackages.stackpanelFullConfig or { };

          storePathsByFile = spConfig.files._storePathsByFile or { };
          snapshot = pkgs.runCommand "files-snapshot" { } (
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
              ) storePathsByFile
            )
          );
        in
        {
          packages = {
            inherit snapshot;
          };

          checks = {
            stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" { } ''
              echo "Fixture: basic"
              echo "stackpanel.enable: ${if spConfig.enable or false then "true" else "false"}"
              touch $out
            '';
          }
          // lib.optionalAttrs (builtins.pathExists ./golden) {
            files-snapshot =
              pkgs.runCommand "files-snapshot-check"
                {
                  nativeBuildInputs = [ pkgs.diffutils ];
                }
                ''
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
        };
    };
}
