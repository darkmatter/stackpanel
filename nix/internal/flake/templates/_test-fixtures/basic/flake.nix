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

    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.stackpanel.flakeModules.readStackpanelRoot
        inputs.stackpanel.flakeModules.default
      ];

      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      perSystem = { pkgs, config, ... }: {
        # Test checks specific to this fixture
        checks = {
          # Verify stackpanel evaluates
          stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" {} ''
            echo "Fixture: basic"
            echo "stackpanel.enable: ${if config.legacyPackages.stackpanelFullConfig.enable or false then "true" else "false"}"
            touch $out
          '';
        };
      };
    };
}
