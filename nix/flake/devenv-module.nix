# ==============================================================================
# devenv-module.nix — Stackpanel as a devenv module (devenvModules.default)
#
# Evaluates the project's .stack config with the same eval/shell code as the
# flake module, then maps the finished shell onto devenv options. Works with
# the devenv CLI (stackpanel as a devenv.yaml input, imported in devenv.nix)
# and with devenv.flakeModule shells (devenv.shells.<name>.imports).
# ==============================================================================
{
  localFlake,
  localInputs,
}:
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # devenv.root is the live project directory, so .stack/ is read in place
  # instead of copying the project into the store.
  self = config.devenv.root;

  stackpanelPkgs = pkgs.appendOverlays registry.overlays;

  eval = import ./per-system/eval.nix {
    inherit
      lib
      self
      inputs
      localFlake
      ;
    pkgs = stackpanelPkgs;
    stackpanelImports = import ./stackpanel-imports.nix {
      inherit lib self inputs;
      inherit (config.stackpanel) autoImportInputs registries;
      extraImports = config.stackpanel.imports;
    };
    flakeLevelStackpanelConfig = { };
    perSystemStackpanelConfig.imports = [
      {
        _module.args.stackpanelDevenvNixd = {
          # flake-parts exposes each named devenv shell, not Stackpanel's
          # top-level outputs. CLI projects need not have a flake at all.
          cli = !(config.devenv.flakesIntegration or false);
          shellName = config._module.args.name or "default";
          sdk = localFlake;
          inherit (localInputs) nixpkgs;
        };
      }
    ];
  };

  registry = import ./integrations {
    inherit
      localFlake
      localInputs
      inputs
      lib
      ;
  };

  shell = import ./per-system/shell.nix {
    inherit lib eval;
    pkgs = stackpanelPkgs;
    extraPackages = registry.extraShellPackages {
      inherit
        config
        lib
        self
        eval
        inputs
        localFlake
        localInputs
        ;
      inherit (stackpanelPkgs.stdenv.hostPlatform) system;
      includeRootOutputs = false;
      inherit (eval) spConfig loadedConfig;
      pkgs = stackpanelPkgs;
    };
  };
in
{
  imports = [ ../stackpanel/core/options/registries.nix ];
  options.stackpanel.imports = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    default = [ ];
    description = "Additional project modules evaluated inside the Stackpanel shell.";
  };
  # Export the actual option fixed point, including explicit/inline imports.
  # Keep it lazy: neither a normal shell nor the author worker needs it.
  options.stackpanel.nixdOptions = lib.mkOption {
    internal = true;
    type = lib.types.raw;
    default = eval.stackpanelEval.options.stackpanel;
  };
  options.shell = lib.mkOption {
    apply = drv: drv // { stackpanelOptions = config.stackpanel.nixdOptions; };
  };
  config = lib.mkIf (eval.spConfig.enable or false) {
    packages = shell.nativeBuildInputs ++ shell.buildInputs;
    env.STACKPANEL_SHELL_HOOK_PATH = shell.STACKPANEL_SHELL_HOOK_PATH;
    enterShell = shell.shellHook;
  };
}
