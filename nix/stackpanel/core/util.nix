# ==============================================================================
# util.nix
#
# Sets up the stackpanel.util helper functions that other modules use.
# Provides logging utilities that respect the debug flag.
#
# Note: The log functions are thunks that check debug at call time to avoid
# infinite recursion during module evaluation.
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  ...
}:
let
  # pkgs is optional - provided by devenv/flakeModule via _module.args
  # or passed directly in specialArgs
  hasPkgs = pkgs != null;

  # Create log functions that lazily check debug flag at call time
  # This avoids evaluating config.stackpanel.debug during module load
  mkLogFn =
    level: v:
    let
      # Evaluate debug lazily when the function is called
      debug = config.stackpanel.debug or false;
      gumLog =
        if hasPkgs then ''${pkgs.gum}/bin/gum log -l ${level} --prefix "stackpanel" "${v}"'' else "";
      echoLog = ''echo "[${lib.toUpper level}] ${v}" >&2'';
    in
    lib.optionalString debug (if hasPkgs then gumLog else echoLog);
in
{
  config = {
    stackpanel.util = {
      log = {
        debug = mkLogFn "debug";
        info = mkLogFn "info";
        error = mkLogFn "error";
        log = mkLogFn "info";
      };
    };

    # Add gum to packages when debug is enabled (evaluated lazily via mkIf)
    stackpanel.devshell.packages = lib.mkIf (hasPkgs && config.stackpanel.debug or false) [ pkgs.gum ];
  };
}
