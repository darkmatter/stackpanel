# Test Fixture: Full Stack
# Tests: All features enabled - multiple apps, modules, services, IDE integration
{
  description = "Test fixture: full stackpanel configuration";

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
          sp = config.legacyPackages.stackpanelFullConfig or { };
          apps = sp.apps or { };
          modules = sp.modules or { };
          files = sp.files.entries or { };
          scripts = sp.scripts or { };

          fileStorePaths = sp.files._storePathsByFile or { };
          snapshot = pkgs.runCommand "files-snapshot" { } (
            ''
              mkdir -p $out
            ''
            + lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                path: storePath:
                if storePath != null then
                  ''
                    mkdir -p "$out/$(dirname '${path}')"
                    cp ${storePath} "$out/${path}"
                  ''
                else
                  ""
              ) fileStorePaths
            )
          );

          hasGolden = builtins.pathExists ./golden;
        in
        {
          packages = {
            inherit snapshot;
          };

          checks = {
            stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" { } ''
              echo "Fixture: full-stack"
              echo "stackpanel.enable: ${if sp.enable or false then "true" else "false"}"
              echo "stackpanel.name: ${sp.name or "unknown"}"
              touch $out
            '';

            apps-defined = pkgs.runCommand "apps-defined-check" { } ''
              apps='${builtins.toJSON (lib.attrNames apps)}'
              echo "Defined apps: $apps"

              ${
                if apps ? web then
                  ''
                    echo "  web app defined"
                  ''
                else
                  ''
                    echo "  ERROR: web app NOT defined"
                    exit 1
                  ''
              }

              ${
                if apps ? server then
                  ''
                    echo "  server app defined"
                  ''
                else
                  ''
                    echo "  ERROR: server app NOT defined"
                    exit 1
                  ''
              }

              ${
                if apps ? docs then
                  ''
                    echo "  docs app defined"
                  ''
                else
                  ''
                    echo "  ERROR: docs app NOT defined"
                    exit 1
                  ''
              }

              touch $out
            '';

            oxlint-enabled = pkgs.runCommand "oxlint-enabled-check" { } ''
              ${
                if modules.oxlint.enable or false then
                  ''
                    echo "OxLint module is enabled"
                  ''
                else
                  ''
                    echo "ERROR: OxLint module is NOT enabled"
                    exit 1
                  ''
              }
              touch $out
            '';

            oxlint-config-generated = pkgs.runCommand "oxlint-config-check" { } ''
              files='${builtins.toJSON (lib.attrNames files)}'
              echo "Generated files: $files"
              if echo "$files" | grep -q "oxlintrc"; then
                echo "OxLint config file is generated"
              else
                echo "ERROR: OxLint config file NOT found"
                exit 1
              fi
              touch $out
            '';

            scripts-defined = pkgs.runCommand "scripts-defined-check" { } ''
              scripts='${builtins.toJSON (lib.attrNames scripts)}'
              echo "Available scripts: $scripts"
              if echo "$scripts" | grep -q "lint"; then
                echo "  lint script exists"
              else
                echo "  WARNING: lint script NOT found"
              fi
              touch $out
            '';

            ide-config = pkgs.runCommand "ide-config-check" { } ''
              ${
                if sp.ide.enable or false then
                  ''
                    echo "IDE integration is enabled"
                  ''
                else
                  ''
                    echo "IDE integration is disabled (expected for test fixture)"
                  ''
              }
              touch $out
            '';

            theme-config = pkgs.runCommand "theme-config-check" { } ''
              ${
                if sp.theme.enable or false then
                  ''
                    echo "Theme is enabled"
                  ''
                else
                  ''
                    echo "Theme is disabled (expected for test fixture)"
                  ''
              }
              touch $out
            '';
          }
          // lib.optionalAttrs hasGolden {
            files-snapshot =
              pkgs.runCommand "files-snapshot-check"
                {
                  nativeBuildInputs = [ pkgs.diffutils ];
                }
                ''
                  diff -ru ${./golden} ${snapshot} || {
                    echo ""
                    echo "══════════════════════════════════════════════════"
                    echo "Snapshot mismatch!"
                    echo "Run update-golden.sh to accept the new output:"
                    echo "  ./nix/flake/templates/_test-fixtures/update-golden.sh full-stack"
                    echo "══════════════════════════════════════════════════"
                    exit 1
                  }
                  touch $out
                '';
          };
        };
    };
}
