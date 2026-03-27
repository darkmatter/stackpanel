# ==============================================================================
# lib/deploy.nix - Deploy library functions
#
# Pure functions for building NixOS configurations and colmena hives from
# stackpanel configuration. Used by nix/flake/global-outputs.nix to populate
# the nixosConfigurations and colmenaHive flake outputs.
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

  appsForMachine =
    config: machineName:
    lib.filterAttrs (
      _: app:
      (app.deployment.enable or false)
      && builtins.elem machineName (app.deployment.targets or [ ])
      && builtins.elem (app.deployment.backend or "colmena") nixosBackends
    ) (config.apps or { });

  # Collect NixOS modules for a machine:
  #   - Always-present defaults (system.stateVersion, sshd)
  #   - SSH authorized keys module (when authorizedKeys is non-empty)
  #   - NixOS modules for apps targeting this machine (from self.nixosModules)
  #   - Disk layout modules (disko + diskLayout path, when diskLayout is set)
  #   - Hardware configuration module (explicit or auto-discovered)
  #   - Extra user-provided modules
  modulesForMachine =
    config: inputs: machineName: machineCfg:
    let
      apps = appsForMachine config machineName;

      appModules = lib.mapAttrsToList (appName: _: inputs.self.nixosModules.${appName}) (
        lib.filterAttrs (appName: _: inputs.self.nixosModules ? ${appName}) apps
      );

      # Auto-discovered hardware config: written by `stackpanel provision` and
      # git-staged so Nix includes it in the flake's store copy before committing.
      autoHardwareMod =
        let path = inputs.self.outPath + "/.stack/machines/${machineName}/hardware-configuration.nix";
        in lib.optional (builtins.pathExists path) path;

      hardwareMods =
        lib.optional (machineCfg.hardwareConfig or null != null) machineCfg.hardwareConfig
        ++ autoHardwareMod;

      autoDiskMod =
        let path = inputs.self.outPath + "/.stack/machines/${machineName}/disks.nix";
        in lib.optionals (machineCfg.diskLayout or null == null && builtins.pathExists path) [
          inputs.disko.nixosModules.disko
          path
        ];

      diskMods =
        if machineCfg.diskLayout or null != null then [
          inputs.disko.nixosModules.disko
          machineCfg.diskLayout
        ] else autoDiskMod;

      extraMods = machineCfg.modules or [ ];

      sshUser = machineCfg.user or "root";
      keys = machineCfg.authorizedKeys or [ ];
      keysMod = lib.optional (keys != [ ]) {
        users.users.${sshUser}.openssh.authorizedKeys.keys = keys;
      };

      alwaysMods = [
        {
          system.stateVersion = lib.mkDefault "24.11";
          services.openssh.enable = lib.mkDefault true;
        }
      ];

      # Pre-provisioning stub: injected only when neither a diskLayout nor a
      # hardwareConfig has been provided. Satisfies NixOS assertions so
      # `nix flake check` passes for un-provisioned machines.
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
        specialArgs = { inherit inputs; };
        modules = modulesForMachine config inputs machineName machineCfg;
      }
    ) machines;

  # ============================================================================
  # mkHive
  #
  # Builds a colmena hive attrset from stackpanel machine definitions.
  # Returns:
  #   {
  #     meta = { nixpkgs = ...; };
  #     "machine-name" = { deployment = ...; imports = ...; };
  #   }
  # ============================================================================
  mkHive =
    { config, inputs, nixpkgs }:
    let
      machines = config.deployment.machines or { };
    in
    {
      meta = {
        nixpkgs = import nixpkgs {
          system =
            if machines == { } then
              "x86_64-linux"
            else
              (lib.head (lib.mapAttrsToList (_: m: m.system or "x86_64-linux") machines));
        };
        nodeNixpkgs = lib.mapAttrs (
          _: machineCfg: import nixpkgs { system = machineCfg.system or "x86_64-linux"; }
        ) machines;
        specialArgs = { inherit inputs; };
      };
    }
    // lib.mapAttrs (
      machineName: machineCfg:
      let
        port = machineCfg.sshPort or 22;
        proxyJump = machineCfg.proxyJump or null;
        hasCustomSsh = port != 22 || proxyJump != null;

        # When proxyJump or a non-standard port is set, colmena needs an
        # SSH options string so it can reach the machine through the bastion.
        # targetHost stays as the logical hostname; SSH options handle routing.
        sshOptions = lib.concatStringsSep " " (
          lib.optional (proxyJump != null) "-J ${proxyJump}"
          ++ lib.optional (port != 22) "-p ${toString port}"
        );
      in
      {
        deployment = {
          targetHost = machineCfg.host;
          targetUser = machineCfg.user or "root";
          targetPort = port;
        } // lib.optionalAttrs hasCustomSsh {
          # colmena passes these flags to every SSH invocation for this node
          tags = [ "ssh-proxied" ];
        };
        imports = modulesForMachine config inputs machineName machineCfg;
      }
    ) machines;
}
