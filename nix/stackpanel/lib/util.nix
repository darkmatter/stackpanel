{
  pkgs,
  lib,
  config,
  ...
}:
let
  debug = config.stackpanel.debug or false;
  logDebug =
    v:
    lib.optionalString debug ''
      ${pkgs.gum}/bin/gum log -l debug --prefix "step" "${v}"
    '';
  logInfo =
    v:
    lib.optionalString debug ''
      ${pkgs.gum}/bin/gum log -l info --prefix "step" "${v}"
    '';
  logError =
    v:
    lib.optionalString debug ''
      ${pkgs.gum}/bin/gum log -l error --prefix "step" "${v}"
    '';
in
{
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
  getConfigValue =
    {
      selector,
      defaultValue,
    }:
    builtins.getAttr selector config.stackpanel or defaultValue;
}
