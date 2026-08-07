# ==============================================================================
# flake-outputs.nix — Top-level flake outputs (nixosModules, config, tests)
# ==============================================================================
{
  lib,
  inputs,
  self,
  localFlake,
  localInputs,
  withSystem,
  stackpanelOverlays,
  stackpanelImports,
  includeRootOutputs,
  primarySystem,
}:
let
  baseNixosModules = {
    default = ../stackpanel/default.nix;
    aws = ../stackpanel/integrations/services/aws;
    network = ../stackpanel/network/network.nix;
    secrets = ../stackpanel/secrets/default.nix;
    theme = ../stackpanel/lib/theme.nix;
    caddy = ../stackpanel/integrations/services/caddy.nix;
    ci = ../stackpanel/apps/ci.nix;
    web-service = ../stackpanel/nixos/web-service.nix;
  };

  globalOutputs = import ./global-outputs.nix {
    inherit inputs self;
    inherit stackpanelImports;
  };

  deploymentTestSystem = "x86_64-linux";
  deploymentTestEnabled = includeRootOutputs && localInputs ? nixtest && localInputs ? namaka;
  deploymentTestInputs =
    let
      pkgs = import localInputs.nixpkgs {
        system = deploymentTestSystem;
        overlays = stackpanelOverlays;
      };
      options = localFlake.lib.getOptions { inherit pkgs; };
    in
    {
      topLevelOptionNames = builtins.attrNames options;
      deploymentOptionNames = builtins.attrNames options.deployment;
      deploymentAlchemyOptionNames = builtins.attrNames options.deployment.alchemy;
    };

  moduleEvalTestInputs = {
    inherit lib;
    pkgs = import localInputs.nixpkgs {
      system = deploymentTestSystem;
      overlays = stackpanelOverlays;
    };
  };

  nixdTestInputs = {
    inherit lib;
    inherit (moduleEvalTestInputs) pkgs;
  };
  nixtestLib = lib.optionalAttrs deploymentTestEnabled (import "${localInputs.nixtest.outPath}/src");
in
{
  flake = {
    flakeInputs = builtins.removeAttrs inputs [ "self" ];
    nixosModules = baseNixosModules // globalOutputs.nixosModules;
    inherit (globalOutputs) nixosConfigurations colmenaHive;

    stackpanelConfig = withSystem primarySystem (
      { config, ... }: config.legacyPackages.stackpanelConfig or { }
    );

    stackpanelFullConfig = withSystem primarySystem (
      { config, ... }: config.legacyPackages.stackpanelFullConfig or { }
    );

    stackpanelRawConfig = withSystem primarySystem (
      { config, ... }: config.legacyPackages.stackpanelRawConfig or { }
    );

    stackpanelPackages = withSystem primarySystem (
      { config, ... }: config.legacyPackages.stackpanelPackages or [ ]
    );

    stackpanelOptions = withSystem primarySystem (
      { config, ... }: config.legacyPackages.stackpanelOptions or { }
    );
  }
  // lib.optionalAttrs deploymentTestEnabled {
    tests = {
      deployment = nixtestLib.assertTests (
        nixtestLib.runTests (import ../stackpanel/integrations/deployment/tests/unit deploymentTestInputs)
      );

      moduleEval = nixtestLib.assertTests (
        nixtestLib.runTests (import ../stackpanel/tests/module-eval moduleEvalTestInputs)
      );

      nixd = nixtestLib.assertTests (
        nixtestLib.runTests (import ../stackpanel/ide/lib/nixd-test.nix nixdTestInputs)
      );
    };

    deploymentSnapshots = localInputs.namaka.lib.load {
      src = ../stackpanel/integrations/deployment/tests/snapshots;
      inputs = deploymentTestInputs;
    };
  };
}
