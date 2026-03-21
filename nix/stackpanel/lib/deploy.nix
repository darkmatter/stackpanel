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
  #   - Always-present defaults (system.stateVersion)
  #   - SSH authorized keys module (when authorizedKeys is non-empty)
  #   - NixOS modules for apps targeting this machine (from self.nixosModules)
  #   - Disk layout modules (disko + diskLayout path, when diskLayout is set)
  #   - Hardware configuration module — either explicit (hardwareConfig option) or
  #     auto-discovered from .stackpanel/hardware/<machineName> when present
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

      # Auto-discovered hardware config: written by `stackpanel provision` (nixos-infect
      # method) and git-staged so Nix includes it in the flake's store copy even before
      # committing.  Eliminates the need to set hardwareConfig = ...; manually.
      autoHardwareMod =
        let path = inputs.self.outPath + "/.stackpanel/hardware/${machineName}";
        in lib.optional (builtins.pathExists path) path;

      # Hardware configuration: explicit option takes precedence; auto-discovered
      # path is appended (both can coexist — NixOS merges module attrsets).
      hardwareMods =
        lib.optional (machineCfg.hardwareConfig or null != null) machineCfg.hardwareConfig
        ++ autoHardwareMod;

      # Disk layout: when diskLayout is set, auto-include the disko NixOS module
      # so the user doesn't have to wire it in manually via `modules`.
      # disko provides fileSystems declarations and (for EF02/BIOS partitions)
      # sets boot.loader.grub.devices automatically — no explicit grub.device needed.
      diskMods = lib.optionals (machineCfg.diskLayout or null != null) [
        inputs.disko.nixosModules.disko
        machineCfg.diskLayout
      ];

      extraMods = machineCfg.modules or [ ];

      sshUser = machineCfg.user or "root";
      keys = machineCfg.authorizedKeys or [ ];
      keysMod = lib.optional (keys != [ ]) {
        users.users.${sshUser}.openssh.authorizedKeys.keys = keys;
      };

      # Always-present defaults (lowest priority, overridden by any real config).
      alwaysMods = [ { system.stateVersion = lib.mkDefault "24.11"; } ];

      # Pre-provisioning stub: injected only when neither a diskLayout nor a
      # hardwareConfig has been provided.  Satisfies NixOS assertions so
      # `nix flake check` passes for un-provisioned machines without producing
      # conflicting values that would break actual provisioning:
      #   - tmpfs root satisfies the "fileSystems must have /" assertion
      #   - grub.enable = false avoids the "must set grub.devices" assertion
      # Both are mkDefault (lowest user priority) so disko overrides them the
      # moment a diskLayout is added.  Note: baseMods is NOT applied once
      # diskLayout is set because diskMods != [] at that point.
      baseMods = lib.optionals (hardwareMods == [ ] && diskMods == [ ]) [
        {
          fileSystems."/" = lib.mkDefault {
            device = "none";
            fsType = "tmpfs";
          };
          boot.loader.grub.enable = lib.mkDefault false;
        }
      ];
    in
    alwaysMods ++ baseMods ++ keysMod ++ appModules ++ diskMods ++ hardwareMods ++ extraMods;
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
