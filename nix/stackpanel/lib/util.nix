{
  pkgs,
  lib,
  config,
  ...
}: let
  debug = config.stackpanel.debug or false;
  # Returns a shell snippet that logs when debug is enabled, or `true` (a
  # shell no-op) when disabled.  Using `true` instead of an empty string
  # keeps these safe as the sole statement inside if/else/fi branches.
  mkLog = level: v:
    if debug
    then ''
      ${pkgs.gum}/bin/gum log -l ${level} --prefix "step" "${v}"
    ''
    else "true";
  logDebug = mkLog "debug";
  logInfo = mkLog "info";
  logError = mkLog "error";
in {
  log = {
    debug = logDebug;
    info = logInfo;
    error = logError;
    log = logInfo;
  };

  # Gets a value from the stackpanel config by default, allowing an override
  # based on an environment variable. To reduce the number of envrionment
  # variable, we use a single JSON encoded variable which matches the structure of
  # the stackpanel config. The key is encoded such that it can be passed to
  # jq to extract the value.
  getConfigValue = {
    selector,
    defaultValue,
  }:
    builtins.getAttr selector config.stackpanel or defaultValue;
}
