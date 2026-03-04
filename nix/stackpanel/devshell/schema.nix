# ==============================================================================
# schema.nix
#
# Schema and option rendering for devshell configuration.
#
# This module handles the transformation of stackpanel.devshell configuration
# into shell initialization code. It processes environment variables and PATH
# modifications, generating shell hooks that set up the development environment.
#
# The rendering order ensures environment setup runs before feature-specific
# hooks, maintaining consistent initialization.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.devshell;
in
{
  imports = [
  ];

  # Base rendering: env + PATH become mkBefore hook parts, so feature hooks run after
  config =
    let
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') cfg.env
      );

      pathPre = lib.concatStringsSep ":" cfg.path.prepend;
      pathApp = lib.concatStringsSep ":" cfg.path.append;

      pathExports = lib.concatStringsSep "\n" (
        lib.filter (s: s != "") [
          (if pathPre == "" then "" else ''export PATH="${pathPre}:$PATH"'')
          (if pathApp == "" then "" else ''export PATH="$PATH:${pathApp}"'')
        ]
      );
    in
    {
      stackpanel.devshell.hooks.before = lib.mkBefore (
        lib.filter (s: s != "") [
          envExports
          pathExports
        ]
      );
    };
}
