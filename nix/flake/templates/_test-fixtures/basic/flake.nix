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

  outputs =
    { self, nixpkgs, flake-utils, stackpanel, ... }@inputs:
    # Use stackpanel.lib.mkFlake for core outputs
    stackpanel.lib.mkFlake { inherit inputs self; }
    # Add test-specific checks
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        spOutputs = stackpanel.lib.mkOutputs {
          inherit inputs self system;
          pkgs = pkgs;
        };
        spConfig = spOutputs.legacyPackages.stackpanelFullConfig or { };
      in
      {
        checks = {
          # Verify stackpanel evaluates
          stackpanel-eval = pkgs.runCommand "stackpanel-eval-check" { } ''
            echo "Fixture: basic"
            echo "stackpanel.enable: ${if spConfig.enable or false then "true" else "false"}"
            touch $out
          '';
        };
      }
    );
}
