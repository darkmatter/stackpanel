# ==============================================================================
# per-system/outputs.nix — Core perSystem outputs from stackpanel eval + shell
# ==============================================================================
{
  lib,
  eval,
  shell,
  localFlake,
  withSystem,
  system,
}:
let
  inherit (eval)
    spConfig
    stackpanelEval
    loadedConfig
    stackpanelSerializable
    allSerializedPackages
    serializeLib
    ;
in
lib.mkMerge [
  {
    _module.args.stackpanel = {
      inherit localFlake;
      packages = withSystem system ({ config, ... }: config.packages or { });
    };
  }

  {
    legacyPackages = {
      stackpanelConfig = stackpanelSerializable;
      stackpanelFullConfig = spConfig;
      stackpanelPackages = allSerializedPackages;
      stackpanelOptions = stackpanelEval.options.stackpanel or { };
      stackpanelRawConfig = serializeLib.filterSerializable loadedConfig;
    };
  }

  (lib.mkIf (spConfig.enable or false) {
    devShells.default = lib.mkForce shell;
  })

  (lib.mkIf (spConfig.enable or false) (
    let
      outputs = spConfig.outputs or { };
      directPkgs = lib.filterAttrs (_: v: lib.isDerivation v) outputs;
      nestedPkgs = lib.filterAttrs (_: v: builtins.isAttrs v && !(lib.isDerivation v)) outputs;
    in
    {
      packages = directPkgs;
      legacyPackages = nestedPkgs;
    }
  ))

  (lib.mkIf (spConfig.enable or false) (
    let
      containersComputed = spConfig.containersComputed or { };
      containerImages = containersComputed.images or { };
      copyScripts = containersComputed.copyScripts or { };
    in
    lib.mkIf (containerImages != { }) {
      packages = lib.mapAttrs' (name: image: {
        name = "container-${name}";
        value = image;
      }) containerImages;

      apps = lib.mapAttrs' (name: script: {
        name = "copy-container-${name}";
        value = {
          type = "app";
          program = "${script}";
        };
      }) (lib.filterAttrs (_: v: v != null) copyScripts);
    }
  ))

  (lib.mkIf (spConfig.enable or false) (
    let
      simpleChecks = spConfig.checks or { };
      moduleChecks = spConfig.moduleChecksFlattened or { };
      allChecks = simpleChecks // moduleChecks;
    in
    lib.mkIf (allChecks != { }) {
      checks = allChecks;
    }
  ))

  (lib.mkIf (spConfig.enable or false) (
    let
      spApps = spConfig.flakeApps or { };
    in
    lib.mkIf (spApps != { }) {
      apps = spApps;
    }
  ))
]
