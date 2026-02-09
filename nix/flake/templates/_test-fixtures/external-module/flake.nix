# Test Fixture: External Module
# Tests: How external modules integrate with stackpanel
#
# Usage for external module testing:
#   nix flake lock --override-input test-module path:/path/to/your-module
#   nix flake check
{
  description = "Test fixture: external module integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Override in CI with: --override-input stackpanel path:/path/to/stackpanel
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;

    # External module to test - override this with your module
    # nix flake lock --override-input test-module path:/path/to/module
    test-module.url = "git+ssh://git@github.com/darkmatter/stackpanel"; # Placeholder
    test-module.flake = false; # Set to true when testing real module
  };

  outputs =
    { self, nixpkgs, flake-utils, stackpanel, ... }@inputs:
    # Use stackpanel.lib.mkFlake for core outputs
    stackpanel.lib.mkFlake { inherit inputs self; }
    # Add test-specific checks
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = stackpanel.lib.requiredOverlays;
        };
        spOutputs = stackpanel.lib.mkOutputs {
          inherit pkgs inputs self system;
        };
        sp = spOutputs.legacyPackages.stackpanelFullConfig or { };

        # Check if test-module is a real module (has stackpanelModules)
        hasTestModule = inputs.test-module ? stackpanelModules;
        testModuleChecks =
          if hasTestModule then inputs.test-module.checks.${system} or { } else { };
      in
      {
        checks =
          {
            # Basic evaluation check
            stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" { } ''
              echo "Fixture: external-module"
              echo "stackpanel.enable: ${if sp.enable or false then "true" else "false"}"
              touch $out
            '';

            # Check if external module is detected
            external-module-detected = pkgs.runCommand "external-module-check" { } ''
              ${
                if hasTestModule then
                  ''
                    echo "✓ External module detected"
                    echo "  Module has stackpanelModules output"
                  ''
                else
                  ''
                    echo "ℹ No external module configured"
                    echo "  Override test-module input to test a module:"
                    echo "  nix flake lock --override-input test-module path:/path/to/module"
                  ''
              }
              touch $out
            '';
          }
          # Merge in the external module's checks if available
          // testModuleChecks;
      }
    );
}
