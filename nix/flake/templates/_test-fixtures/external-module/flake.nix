# Test Fixture: External Module
# Tests: How external modules integrate with stackpanel
{
  description = "Test fixture: external module integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Override in CI with: --override-input stackpanel git+file:/path/to/stackpanel
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";

    # External module to test - override this with your module
    # nix flake lock --override-input test-module path:/path/to/module
    test-module.url = "git+ssh://git@github.com/darkmatter/stackpanel";
    test-module.flake = false;
  };

  outputs =
    { self, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake {
      inherit inputs self;

      perSystem =
        { pkgs, config, ... }:
        let
          sp = config.legacyPackages.stackpanelFullConfig or { };
          hasTestModule = inputs.test-module ? stackpanelModules;
          testModuleChecks = if hasTestModule then inputs.test-module.checks.${pkgs.system} or { } else { };
        in
        {
          checks = {
            stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" { } ''
              echo "Fixture: external-module"
              echo "stackpanel.enable: ${if sp.enable or false then "true" else "false"}"
              touch $out
            '';

            external-module-detected = pkgs.runCommand "external-module-check" { } ''
              ${
                if hasTestModule then
                  ''
                    echo "External module detected"
                    echo "  Module has stackpanelModules output"
                  ''
                else
                  ''
                    echo "No external module configured"
                    echo "  Override test-module input to test a module:"
                    echo "  nix flake lock --override-input test-module path:/path/to/module"
                  ''
              }
              touch $out
            '';
          }
          // testModuleChecks;
        };
    };
}
