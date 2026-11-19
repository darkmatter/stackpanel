{
  lib,
  cfg,
  inputs,
}:
let
  # A configurable namespace may contain build outputs or secret stores;
  # publish only settings declared by the UI schema.
  settingsFor =
    mod:
    let
      schema = if mod.configSchema == null then { } else builtins.fromJSON mod.configSchema;
      # Package settings can be thunks over an unavailable pkgs (global
      # eval) or expensive build graphs. Check schema before touching them.
      containsPackage =
        s:
        (s.format or null) == "nix-store-path"
        || (s ? items && containsPackage s.items)
        || (builtins.isAttrs (s.additionalProperties or null) && containsPackage s.additionalProperties)
        || builtins.any containsPackage (s.anyOf or [ ]);
      project =
        s: value:
        if s ? properties && builtins.isAttrs value then
          lib.mapAttrs (k: project s.properties.${k}) (
            builtins.intersectAttrs (lib.filterAttrs (_: v: !(containsPackage v)) s.properties) value
          )
        else
          value;
      settings = lib.attrByPath (lib.splitString "." mod.configPath) { } cfg;
    in
    if (schema.properties or { }) == { } then
      { }
    else
      (import ../../../lib/serialize.nix { inherit lib; }).filterSerializableWithSkip [ ] (
        project schema settings
      );

  # A lib.getExe store path carries its producing derivation in its string
  # context. Preserve that reference for on-demand realization by the agent.
  actionMetadata =
    action:
    let
      producers = lib.filterAttrs (_: ref: (ref.outputs or [ ]) != [ ]) (
        builtins.getContext action.script
      );
      paths = builtins.attrNames producers;
    in
    action // { scriptDrvPath = if builtins.length paths == 1 then builtins.head paths else null; };

  computeSerializableModule = name: mod: {
    id = name;
    enabled = mod.enable;
    inherit (mod)
      meta
      source
      features
      priority
      tags
      requires
      conflicts
      flakeInputs
      configPath
      enablePath
      readme
      configSchema
      apps
      healthcheckModule
      ;
    actions = lib.mapAttrs (_: actionMetadata) mod.actions;
    missingFlakeInputs = builtins.filter (input: !(builtins.hasAttr input.name inputs)) mod.flakeInputs;
    settings = settingsFor mod;
  };
in
lib.mapAttrs computeSerializableModule cfg.modules
