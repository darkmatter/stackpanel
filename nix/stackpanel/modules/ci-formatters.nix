# ==============================================================================
# ci-formatters.nix
#
# Flake checks for formatter tooling.
# Runs wrapped formatters in a writable copy of the repo for CI usage.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;
  appsComputed = cfg.appsComputed or { };
  repoRoot = ../../..;

  formatters = lib.flatten (
    lib.mapAttrsToList (_: app: app.wrappedTooling.formatters or [ ]) appsComputed
  );

  formatterCheck =
    pkgs.runCommand "stackpanel-formatters"
      {
        nativeBuildInputs = formatters;
      }
      ''
        if [ "${toString (formatters == [ ])}" = "1" ]; then
          touch "$out"
          exit 0
        fi

        export STACKPANEL_ROOT="$PWD/src"
        cp -R ${repoRoot} "$STACKPANEL_ROOT"
        chmod -R u+w "$STACKPANEL_ROOT"
        cd "$STACKPANEL_ROOT"

        ${lib.concatMapStringsSep "\n" (tool: "${lib.getExe tool}") formatters}

        touch "$out"
      '';
in
{
  config = lib.mkIf cfg.enable {
    stackpanel.checks = lib.optionalAttrs (formatters != [ ]) {
      formatters = formatterCheck;
    };
  };
}
