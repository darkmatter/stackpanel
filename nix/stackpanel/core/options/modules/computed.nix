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
      name = mod.meta.name;
      description = mod.meta.description;
      icon = mod.meta.icon;
      category = mod.meta.category;
      author = mod.meta.author;
      version = mod.meta.version;
      homepage = mod.meta.homepage;
    };
    source = {
      type = mod.source.type;
      flakeInput = mod.source.flakeInput;
      path = mod.source.path;
      registryId = mod.source.registryId;
      ref = mod.source.ref;
    };
    features = {
      files = mod.features.files;
      scripts = mod.features.scripts;
      tasks = mod.features.tasks;
      healthchecks = mod.features.healthchecks;
      services = mod.features.services;
      secrets = mod.features.secrets;
      packages = mod.features.packages;
      appModule = mod.features.appModule;
    };
    requires = mod.requires;
    conflicts = mod.conflicts;
    flakeInputs = map (fi: {
      name = fi.name;
      url = fi.url;
      followsNixpkgs = fi.followsNixpkgs;
    }) mod.flakeInputs;
    priority = mod.priority;
    tags = mod.tags;
    configSchema = mod.configSchema;
    panels = map (panel: {
      id = panel.id;
      title = panel.title;
      description = panel.description;
      type = panel.type;
      order = panel.order;
      fields = map (field: {
        name = field.name;
        type = field.type;
        value = field.value;
        options = field.options;
      }) panel.fields;
    }) mod.panels;
    apps = lib.mapAttrs (_: appData: {
      enabled = appData.enabled;
      config = appData.config;
    }) mod.apps;
    healthcheckModule = mod.healthcheckModule;
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
