{
  lib,
  cfg,
}:
let
  # ==========================================================================
  # Computed Values
  # ==========================================================================

  # Filter to only enabled modules
  enabledModules = lib.filterAttrs (_: mod: mod.enable) cfg.modules;

  # Get builtin modules
  builtinModules = lib.filterAttrs (_: mod: mod.source.type == "builtin") enabledModules;

  # Get external modules (local, flake-input, registry)
  externalModules = lib.filterAttrs (_: mod: mod.source.type != "builtin") enabledModules;

  # Compute serializable module data (for API/UI consumption)
  computeSerializableModule = name: mod: {
    id = name;
    enabled = mod.enable;
    meta = {
      inherit (mod.meta) name;
      inherit (mod.meta) description;
      inherit (mod.meta) icon;
      inherit (mod.meta) category;
      inherit (mod.meta) author;
      inherit (mod.meta) version;
      inherit (mod.meta) homepage;
    };
    source = {
      inherit (mod.source) type;
      inherit (mod.source) flakeInput;
      inherit (mod.source) path;
      inherit (mod.source) registryId;
      inherit (mod.source) ref;
    };
    features = {
      inherit (mod.features) files;
      inherit (mod.features) scripts;
      inherit (mod.features) tasks;
      inherit (mod.features) healthchecks;
      inherit (mod.features) services;
      inherit (mod.features) secrets;
      inherit (mod.features) packages;
      inherit (mod.features) appModule;
    };
    inherit (mod) requires;
    inherit (mod) conflicts;
    flakeInputs = map (fi: {
      inherit (fi) name;
      inherit (fi) url;
      inherit (fi) followsNixpkgs;
    }) mod.flakeInputs;
    inherit (mod) priority;
    inherit (mod) tags;
    inherit (mod) configSchema;
    panels = map (panel: {
      inherit (panel) id;
      inherit (panel) title;
      inherit (panel) description;
      inherit (panel) type;
      inherit (panel) order;
      fields = map (field: {
        inherit (field) name;
        inherit (field) type;
        inherit (field) value;
        inherit (field) options;
      }) panel.fields;
    }) mod.panels;
    apps = lib.mapAttrs (_: appData: {
      inherit (appData) enabled;
      inherit (appData) config;
    }) mod.apps;
    inherit (mod) healthcheckModule;
  };

  # All modules as serializable attrset
  modulesComputed = lib.mapAttrs computeSerializableModule cfg.modules;

  # Enabled modules only
  modulesComputedEnabled = lib.mapAttrs computeSerializableModule enabledModules;

  # Flat list for API consumption
  modulesList = lib.mapAttrsToList computeSerializableModule cfg.modules;
  modulesListEnabled = lib.mapAttrsToList computeSerializableModule enabledModules;

in
{
  inherit
    enabledModules
    builtinModules
    externalModules
    computeSerializableModule
    modulesComputed
    modulesComputedEnabled
    modulesList
    modulesListEnabled
    ;
}
