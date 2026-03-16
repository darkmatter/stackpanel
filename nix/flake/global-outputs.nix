# ==============================================================================
# global-outputs.nix - Stackpanel Global (Non-Per-System) Flake Outputs
#
# A pure function that generates system-agnostic flake outputs.
# Usage:
#   import ./global-outputs.nix { inherit inputs self; }
#
# Returns:
#   { nixosModules, nixosConfigurations, colmenaHive }
#
# Architecture:
#   - Uses lib.evalModules with inputs.nixpkgs.lib (no pkgs instantiation).
#   - Deploy config (deployment.machines, apps.*.deployment.*) is purely
#     declarative and never forces pkgs — lazy evaluation keeps it safe.
#   - pkgs is replaced with a lib.warn + throw stub: if any module
#     accidentally accesses it, evaluation fails with a clear message.
#   - Each machine's NixOS configuration uses that machine's declared
#     `system` via nixpkgs.lib.nixosSystem, so there is no hardcoded
#     build host system anywhere in this path.
#
# Future non-deploy global outputs (overlays, templates, etc.) should
# also live here rather than in per-system-outputs.nix.
# ==============================================================================
{
  inputs,
  self,
  stackpanelImports ? [ ],
}:
let
  lib = inputs.nixpkgs.lib;

  # ===================================================================
  # Auto-load stackpanel config from .stackpanel/
  # ===================================================================
  configPath = import ./load-config.nix { inherit self; };

  loadConfig =
    path:
    let
      raw = import path;
    in
    # Function-style configs that take pkgs are called with null here;
    # the deploy module never uses pkgs so this is safe.
    if builtins.isFunction raw then raw { inherit lib; pkgs = null; } else raw;

  loadedConfig = if configPath != null then loadConfig configPath else { };

  # ===================================================================
  # Evaluate stackpanel modules — lib only, no pkgs instantiation
  #
  # pkgs is intentionally replaced with a warn+throw stub.  The deploy
  # module and all its option definitions are pure lib; lazy evaluation
  # means this stub is never forced.  If a future module accidentally
  # reaches for pkgs in this path, evaluation fails loudly rather than
  # silently producing a wrong result.
  # ===================================================================
  stubPkgs = lib.warn
    "stackpanel global-outputs: a module accessed `pkgs`, which is not available in the lib-only eval path. Move any pkgs-dependent logic to per-system-outputs.nix."
    (throw "pkgs is not available in global-outputs eval");

  stackpanelEval = lib.evalModules {
    modules = [
      ../stackpanel
      { stackpanel = loadedConfig; }
    ]
    ++ stackpanelImports;
    specialArgs = {
      inherit lib inputs self;
      pkgs = stubPkgs;
    };
  };

  spConfig = stackpanelEval.config.stackpanel;
  enabled = spConfig.enable or false;
  hasNixpkgs = inputs ? nixpkgs;

  deployLib = import ../stackpanel/lib/deploy.nix { inherit lib; };
  deployArgs = {
    config = spConfig;
    inherit inputs;
    nixpkgs = inputs.nixpkgs or null;
  };

in
{
  # Per-app NixOS service modules (generated from apps with NixOS backends).
  # These are system-agnostic: the modules themselves reference
  # inputs.self.packages.${system} lazily at NixOS evaluation time.
  nixosModules = if enabled then spConfig.nixosModules or { } else { };

  # Full NixOS system configs per machine.
  # Each machine uses its own declared `system` via nixpkgs.lib.nixosSystem.
  nixosConfigurations =
    if enabled && hasNixpkgs then deployLib.mkNixosConfigurations deployArgs else { };

  # Colmena hive for multi-machine deployment (colmena apply).
  colmenaHive =
    if enabled && hasNixpkgs then deployLib.mkHive deployArgs else { };
}
