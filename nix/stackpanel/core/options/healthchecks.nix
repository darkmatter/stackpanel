# ==============================================================================
# healthchecks.nix - Health panel over runtime-scope doctor checks
#
# Runtime probes are declared under `stackpanel.doctor.<module>.<name>` (see
# doctor.nix). This module only owns the studio "System Health" panel and its
# enable switch. The agent API keeps consuming the `healthchecksComputed` /
# `healthchecksList` views, which doctor.nix derives with the unchanged
# `Healthcheck` wire shape and `HEALTHCHECK_TYPE_*` enum strings:
#   🟢 Green  - All checks passing
#   🟡 Yellow - Some non-critical checks failing
#   🔴 Red    - Critical checks failing
#   ⚪ Grey   - Checks haven't run or are disabled
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.healthchecks;

  runtimeChecksOf =
    mod:
    lib.filterAttrs (_: c: c.scope == "runtime") (
      builtins.removeAttrs mod [
        "enable"
        "displayName"
      ]
    );

  enabledModules = lib.filterAttrs (
    _: mod: mod.enable && runtimeChecksOf mod != { }
  ) config.stackpanel.doctor;
in
{
  options.stackpanel.healthchecks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the healthcheck UI panel built from runtime-scope doctor checks.";
      example = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # Register healthchecks module panel for the UI (not an extension - core module)
    stackpanel.panels.healthchecks-overview = {
      module = "healthchecks";
      title = "System Health";
      description = "Overview of healthcheck status across enabled Stackpanel modules";
      icon = "activity";
      type = "PANEL_TYPE_STATUS";
      order = 5;
      fields = [
        {
          name = "metrics";
          type = "FIELD_TYPE_STRING";
          value = builtins.toJSON (
            lib.mapAttrsToList (
              _moduleName: mod:
              let
                enabledChecks = lib.filterAttrs (_: c: c.enable) (runtimeChecksOf mod);
                enabledCount = lib.length (lib.attrNames enabledChecks);
              in
              {
                label = mod.displayName;
                value = "${toString enabledCount} checks";
                status = if enabledCount > 0 then "ok" else "warning";
              }
            ) enabledModules
          );
        }
      ];
      # Include module summary as app data
      apps = lib.mapAttrs (_moduleName: mod: {
        enabled = mod.enable;
        config = {
          inherit (mod) displayName;
          checkCount = toString (lib.length (lib.attrNames (runtimeChecksOf mod)));
        };
      }) enabledModules;
    };
  };
}
