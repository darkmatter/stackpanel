# ==============================================================================
# lib/deploy.nix - Deploy library functions
#
# Pure functions for building NixOS configurations and colmena hives from
# stackpanel configuration. These are used by nix/flake/default.nix to
# populate the nixosConfigurations and colmenaHive flake outputs.
#
# Usage:
#   let deployLib = import ./deploy.nix { inherit lib; };
#   in {
#     nixosConfigurations = deployLib.mkNixosConfigurations {
#       config = spConfig;
#       inherit inputs;
#       nixpkgs = inputs.nixpkgs;
#     };
#     colmenaHive = deployLib.mkHive {
#       config = spConfig;
#       inherit inputs;
#       nixpkgs = inputs.nixpkgs;
#     };
#   }
# ==============================================================================
{ lib }:
let
  nixosBackends = [
    "colmena"
    "nixos-rebuild"
  ];

  # Filter apps that target a given machine name with a NixOS backend
  appsForMachine =
    config: machineName:
    lib.filterAttrs (
      _: app:
      (app.deployment.enable or false)
      && builtins.elem machineName (app.deployment.targets or [ ])
      && builtins.elem (app.deployment.backend or "colmena") nixosBackends
    ) (config.apps or { });

  # Collect the NixOS modules for a machine:
  #   - Base module: mkDefault values satisfying NixOS assertions (no hardware needed)
  #   - SSH authorized keys module (when authorizedKeys is non-empty)
  #   - NixOS modules for apps targeting this machine (from self.nixosModules)
  #   - Hardware configuration module (if provided) — overrides base module defaults
  #   - Extra user-provided modules
  modulesForMachine =
    config: inputs: machineName: machineCfg:
    let
      apps = appsForMachine config machineName;

      # For each app targeting this machine, reference its NixOS module from
      # the flake's nixosModules output.  We guard against missing entries
      # (shouldn't happen, but be safe).
      appModules = lib.mapAttrsToList (appName: _: inputs.self.nixosModules.${appName}) (
        lib.filterAttrs (appName: _: inputs.self.nixosModules ? ${appName}) apps
      );

      # Hardware configuration: pass the path directly — NixOS accepts paths as modules
      hardwareMods = lib.optional (machineCfg.hardwareConfig or null != null) machineCfg.hardwareConfig;

      extraMods = machineCfg.modules or [ ];

      sshUser = machineCfg.user or "root";
      keys = machineCfg.authorizedKeys or [ ];
      keysMod = lib.optional (keys != [ ]) {
        users.users.${sshUser}.openssh.authorizedKeys.keys = keys;
      };

      # Minimal defaults that satisfy NixOS assertions so `nix flake check` passes
      # for machines that don't yet have a hardwareConfig (e.g. pre-provisioning).
      # Only injected when hardwareConfig is absent — once a real hardware config is
      # provided it takes full responsibility for boot/filesystem declarations and
      # any omission there should surface as an error, not be silently papered over.
      baseMods = lib.optionals (hardwareMods == [ ]) [
        {
          boot.loader.grub.device = lib.mkDefault "/dev/sda";
          fileSystems."/" = lib.mkDefault {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          system.stateVersion = lib.mkDefault "24.11";
        }
      ];
    in
    baseMods ++ keysMod ++ appModules ++ hardwareMods ++ extraMods;
in
{
  # ============================================================================
  # mkNixosConfigurations
  #
  # Builds a nixosConfigurations attrset from stackpanel machine definitions.
  # Pass this to the flake's nixosConfigurations output.
  #
  # Returns: { "machine-name" = nixpkgs.lib.nixosSystem { ... }; ... }
  # ============================================================================
  mkNixosConfigurations =
    { config, inputs, nixpkgs }:
    let
      machines = config.deployment.machines or { };
    in
    lib.mapAttrs (
      machineName: machineCfg:
      nixpkgs.lib.nixosSystem {
        system = machineCfg.system or "x86_64-linux";
        # Make inputs available as specialArgs so NixOS modules can reference
        # inputs.self.packages.${system}.${appName} for ExecStart, etc.
        specialArgs = { inherit inputs; };
        modules = modulesForMachine config inputs machineName machineCfg;
      }
    ) machines;

  # ============================================================================
  # mkHive
  #
  # Builds a colmena hive attrset from stackpanel machine definitions.
  # Pass this to the flake's colmenaHive output.
  #
  # Returns:
  #   {
  #     meta = { nixpkgs = import nixpkgs { system = "x86_64-linux"; }; };
  #     "machine-name" = {
  #       deployment = { targetHost = "..."; targetUser = "..."; };
  #       imports = [ ... ];
  #     };
  #   }
  # ============================================================================
  mkHive =
    { config, inputs, nixpkgs }:
    let
      machines = config.deployment.machines or { };
    in
    {
      meta = {
        # Fallback nixpkgs for the hive (used for machines without an explicit
        # system override).  Derived from the first declared machine's system
        # so we avoid hardcoding x86_64-linux.
        nixpkgs = import nixpkgs {
          system =
            if machines == { } then
              "x86_64-linux"
            else
              (lib.head (lib.mapAttrsToList (_: m: m.system or "x86_64-linux") machines));
        };
        # Per-node nixpkgs — each machine gets a nixpkgs instance for its own
        # declared system, eliminating any remaining cross-system assumptions.
        nodeNixpkgs = lib.mapAttrs (
          _: machineCfg: import nixpkgs { system = machineCfg.system or "x86_64-linux"; }
        ) machines;
      };
    }
    // lib.mapAttrs (
      machineName: machineCfg:
      {
        deployment = {
          targetHost = machineCfg.host;
          targetUser = machineCfg.user or "root";
        };
        imports = modulesForMachine config inputs machineName machineCfg;
      }
    ) machines;
}
