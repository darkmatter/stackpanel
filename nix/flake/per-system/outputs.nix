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

      # Speculative evaluation for `stack setup`: re-evaluate with the accepted
      # addon config mutations overlaid and return only what the reconciler
      # needs to render a plan. Evaluate with `nix eval --json --apply`.
      #   nix eval --json .#legacyPackages.<system>.stackpanelSpeculate \
      #     --apply 'f: f { config = { modules.playwright.enable = true; }; }'
      stackpanelSpeculate =
        {
          modules ? [ ],
          config ? { },
        }:
        let
          sp = (eval.evalWith (modules ++ [ { stackpanel = config; } ])).config.stackpanel;
          writer = sp.files._writerDrv;
        in
        {
          files = sp.files._plan;
          doctor = sp.doctorList;
          addons = sp.addonsList;
          writerDrvPath = builtins.toString writer.drvPath;
          writerOutPath = builtins.toString writer;
          preflightManifestDrvPath = builtins.toString sp.files._preflightManifestDrv.drvPath;
          preflightManifestOutPath = builtins.toString sp.files._preflightManifestDrv;
        };
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
