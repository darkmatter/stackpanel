# ==============================================================================
# ui.nix - Colmena UI Panel Definitions
#
# Defines the panels that appear in the Stackpanel UI for this module.
#
# Panels:
# - Status panel: Shows enabled state, hive config, flake reference
# - Config form: Editable form for all Colmena options with configPath mappings
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  meta = import ./meta.nix;
  sp = config.stackpanel;
  cfg = sp.colmena;

  toBool = value: if value then "true" else "false";
  toJson = value: builtins.toJSON value;
  toNumOrEmpty = value: if value == null then "" else toString value;
  flakeDisplay = if cfg.flake != null then cfg.flake else "(not set)";
  flakeInputValue = if cfg.flake != null then cfg.flake else "";
in
{
  stackpanel.panels."${meta.id}-status" = lib.mkIf (sp.enable && cfg.enable) {
    module = meta.id;
    title = "Colmena";
    inherit (meta) description;
    inherit (meta) icon;
    type = "PANEL_TYPE_STATUS";
    order = meta.priority;
    fields = [
      {
        name = "metrics";
        type = "FIELD_TYPE_STRING";
        value = toJson [
          {
            label = "Enabled";
            value = if cfg.enable then "Yes" else "No";
            status = if cfg.enable then "ok" else "warning";
          }
          {
            label = "Hive Config";
            value = cfg.config;
            status = "ok";
          }
          {
            label = "Flake";
            value = flakeDisplay;
            status = "ok";
          }
        ];
      }
    ];
  };

  stackpanel.panels."${meta.id}-config" = lib.mkIf sp.enable {
    module = meta.id;
    title = "Colmena Settings";
    description = "Configure Colmena defaults used by stackpanel scripts";
    inherit (meta) icon;
    type = "PANEL_TYPE_FORM";
    order = meta.priority + 1;
    fields = [
      {
        name = "enable";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Enable Colmena";
        description = "Enable Colmena tooling, scripts, and health checks";
        value = toBool cfg.enable;
        configPath = "colmena.enable";
      }
      {
        name = "config";
        type = "FIELD_TYPE_STRING";
        label = "Hive Config Path";
        description = "Path to the Colmena hive config file";
        value = cfg.config;
        configPath = "colmena.config";
      }
      {
        name = "flake";
        type = "FIELD_TYPE_STRING";
        label = "Flake Reference";
        description = "Optional flake target to use instead of plain hive file";
        value = flakeInputValue;
        placeholder = ".#colmena";
        configPath = "colmena.flake";
      }
      {
        name = "on";
        type = "FIELD_TYPE_JSON";
        label = "Target Filter";
        description = "List of node names, tags, or patterns passed to --on";
        value = toJson cfg.on;
        configPath = "colmena.on";
      }
      {
        name = "exclude";
        type = "FIELD_TYPE_JSON";
        label = "Exclude Filter";
        description = "List of node names, tags, or patterns passed to --exclude";
        value = toJson cfg.exclude;
        configPath = "colmena.exclude";
      }
      {
        name = "keepResult";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Keep Result";
        description = "Keep build results in GC roots";
        value = toBool cfg.keepResult;
        configPath = "colmena.keepResult";
      }
      {
        name = "verbose";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Verbose";
        description = "Enable verbose Colmena output";
        value = toBool cfg.verbose;
        configPath = "colmena.verbose";
      }
      {
        name = "showTrace";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Show Trace";
        description = "Show detailed Nix traces on errors";
        value = toBool cfg.showTrace;
        configPath = "colmena.showTrace";
      }
      {
        name = "impure";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Impure Eval";
        description = "Allow impure Nix evaluation";
        value = toBool cfg.impure;
        configPath = "colmena.impure";
      }
      {
        name = "evalNodeLimit";
        type = "FIELD_TYPE_NUMBER";
        label = "Eval Node Limit";
        description = "Maximum nodes evaluated concurrently";
        value = toNumOrEmpty cfg.evalNodeLimit;
        configPath = "colmena.evalNodeLimit";
      }
      {
        name = "parallel";
        type = "FIELD_TYPE_NUMBER";
        label = "Parallel Jobs";
        description = "Maximum concurrent deployment jobs";
        value = toNumOrEmpty cfg.parallel;
        configPath = "colmena.parallel";
      }
      {
        name = "buildOnTarget";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Build On Target";
        description = "Build closures on target nodes";
        value = toBool cfg.buildOnTarget;
        configPath = "colmena.buildOnTarget";
      }
      {
        name = "uploadKeys";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Upload Keys";
        description = "Upload deployment keys before activation";
        value = toBool cfg.uploadKeys;
        configPath = "colmena.uploadKeys";
      }
      {
        name = "noSubstitute";
        type = "FIELD_TYPE_BOOLEAN";
        label = "No Substitute";
        description = "Disable binary cache substitution";
        value = toBool cfg.noSubstitute;
        configPath = "colmena.noSubstitute";
      }
      {
        name = "substituteOnDestination";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Substitute On Destination";
        description = "Allow substitution on destination nodes";
        value = toBool cfg.substituteOnDestination;
        configPath = "colmena.substituteOnDestination";
      }
      {
        name = "gzip";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Gzip Transfers";
        description = "Compress closure transfer streams";
        value = toBool cfg.gzip;
        configPath = "colmena.gzip";
      }
      {
        name = "reboot";
        type = "FIELD_TYPE_BOOLEAN";
        label = "Allow Reboot";
        description = "Allow reboots when required by activation";
        value = toBool cfg.reboot;
        configPath = "colmena.reboot";
      }
      {
        name = "extraFlags";
        type = "FIELD_TYPE_JSON";
        label = "Extra Flags";
        description = "Extra flags appended to every colmena command";
        value = toJson cfg.extraFlags;
        configPath = "colmena.extraFlags";
      }
      {
        name = "applyExtraFlags";
        type = "FIELD_TYPE_JSON";
        label = "Apply Extra Flags";
        description = "Extra flags for colmena-apply only";
        value = toJson cfg.applyExtraFlags;
        configPath = "colmena.applyExtraFlags";
      }
      {
        name = "buildExtraFlags";
        type = "FIELD_TYPE_JSON";
        label = "Build Extra Flags";
        description = "Extra flags for colmena-build only";
        value = toJson cfg.buildExtraFlags;
        configPath = "colmena.buildExtraFlags";
      }
      {
        name = "evalExtraFlags";
        type = "FIELD_TYPE_JSON";
        label = "Eval Extra Flags";
        description = "Extra flags for colmena-eval only";
        value = toJson cfg.evalExtraFlags;
        configPath = "colmena.evalExtraFlags";
      }
    ];
  };
}
