# Test Fixture: Full Stack
# Tests: All features enabled - multiple apps, modules, services, IDE integration
#
# Usage:
#   nix flake check --override-input stackpanel path:/path/to/stackpanel --no-write-lock-file
{
  description = "Test fixture: full stackpanel configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Override in CI with: --override-input stackpanel path:/path/to/stackpanel
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs =
    { self, nixpkgs, flake-utils, stackpanel, ... }@inputs:
    # Use stackpanel.lib.mkFlake for core outputs
    stackpanel.lib.mkFlake { inherit inputs self; }
    # Add comprehensive test checks
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = stackpanel.lib.requiredOverlays;
        };
        lib = pkgs.lib;
        spOutputs = stackpanel.lib.mkOutputs {
          inherit pkgs inputs self system;
        };
        sp = spOutputs.legacyPackages.stackpanelFullConfig or { };
        apps = sp.apps or { };
        modules = sp.modules or { };
        files = sp.files.entries or { };
        scripts = sp.scripts or { };
      in
      {
        checks = {
          # =====================================================
          # Core evaluation
          # =====================================================
          stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" { } ''
            echo "Fixture: full-stack"
            echo "stackpanel.enable: ${if sp.enable or false then "true" else "false"}"
            echo "stackpanel.name: ${sp.name or "unknown"}"
            touch $out
          '';

          # =====================================================
          # Multiple apps
          # =====================================================
          apps-defined = pkgs.runCommand "apps-defined-check" { } ''
            apps='${builtins.toJSON (lib.attrNames apps)}'
            echo "Defined apps: $apps"

            # Check web app
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

            # Check server app
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

            # Check docs app
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

          # =====================================================
          # OxLint module
          # =====================================================
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

          # =====================================================
          # Scripts
          # =====================================================
          scripts-defined = pkgs.runCommand "scripts-defined-check" { } ''
            scripts='${builtins.toJSON (lib.attrNames scripts)}'
            echo "Available scripts: $scripts"

            # Check lint script exists
            if echo "$scripts" | grep -q "lint"; then
              echo "  lint script exists"
            else
              echo "  WARNING: lint script NOT found"
            fi

            touch $out
          '';

          # =====================================================
          # IDE integration
          # =====================================================
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

          # =====================================================
          # Theme
          # =====================================================
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
        };
      }
    );
}
