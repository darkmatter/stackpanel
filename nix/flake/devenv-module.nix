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
  self = /. + config.devenv.root;

  stackpanelPkgs = pkgs.appendOverlays (import ./overlays.nix { inherit localInputs; });

  eval = import ./per-system/eval.nix {
    inherit
      lib
      self
      inputs
      localFlake
      ;
    pkgs = stackpanelPkgs;
    stackpanelImports = import ./stackpanel-imports.nix { inherit lib self; };
    flakeLevelStackpanelConfig = { };
    perSystemStackpanelConfig = { };
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
      inherit lib self eval;
      inherit (eval) spConfig loadedConfig;
      pkgs = stackpanelPkgs;
    };
  };
in
lib.mkIf (eval.spConfig.enable or false) {
  packages = shell.nativeBuildInputs ++ shell.buildInputs;
  env.STACKPANEL_SHELL_HOOK_PATH = shell.STACKPANEL_SHELL_HOOK_PATH;
  enterShell = shell.shellHook;
}
