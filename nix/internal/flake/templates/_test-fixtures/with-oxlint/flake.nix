# Test Fixture: With OxLint
# Tests: OxLint module, file generation, scripts, health checks
#
# Usage:
#   nix flake check --override-input stackpanel path:/path/to/stackpanel --no-write-lock-file
{
  description = "Test fixture: stackpanel with oxlint module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Override in CI with: --override-input stackpanel path:/path/to/stackpanel
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.stackpanel.flakeModules.readStackpanelRoot
        inputs.stackpanel.flakeModules.default
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {
        pkgs,
        config,
        lib,
        ...
      }: let
        sp = config.legacyPackages.stackpanelFullConfig or {};

        # ── Snapshot ─────────────────────────────────────────────────
        # Assemble all generated file contents into a single derivation
        # for golden-file comparison.
        storePathsByFile = sp.files._storePathsByFile or {};
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

        hasGolden = builtins.pathExists ./golden;
      in {
        packages = {
          inherit snapshot;
        };

        checks =
          {
            # Verify oxlint module is enabled
            oxlint-enabled = pkgs.runCommand "oxlint-enabled-check" {} ''
              ${
                if sp.modules.oxlint.enable or false
                then ''
                  echo "✓ OxLint module is enabled"
                ''
                else ''
                  echo "✗ OxLint module is NOT enabled"
                  exit 1
                ''
              }
              touch $out
            '';

            # Verify oxlint generates config files
            oxlint-files = pkgs.runCommand "oxlint-files-check" {} ''
              files='${builtins.toJSON (lib.attrNames (sp.files.entries or {}))}'
              echo "Generated files: $files"
              if echo "$files" | grep -q "oxlintrc"; then
                echo "✓ OxLint config file is generated"
              else
                echo "✗ OxLint config file NOT found in generated files"
                exit 1
              fi
              touch $out
            '';

            # Verify lint scripts exist
            oxlint-scripts = pkgs.runCommand "oxlint-scripts-check" {} ''
              scripts='${builtins.toJSON (lib.attrNames (sp.scripts or {}))}'
              echo "Available scripts: $scripts"
              if echo "$scripts" | grep -q "lint"; then
                echo "✓ Lint script exists"
              else
                echo "✗ Lint script NOT found"
                exit 1
              fi
              touch $out
            '';
          }
          // lib.optionalAttrs hasGolden {
            # Compare generated files against checked-in golden directory
            files-snapshot =
              pkgs.runCommand "files-snapshot-check" {
                nativeBuildInputs = [pkgs.diffutils];
              } ''
                diff -ru ${./golden} ${snapshot} && echo "✓ Snapshot matches golden files" || {
                  echo ""
                  echo "✗ Snapshot mismatch! Update golden files with:"
                  echo "  ./update-golden.sh with-oxlint"
                  exit 1
                }
                touch $out
              '';
          };
      };
    };
}
