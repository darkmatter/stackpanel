# ==============================================================================
# app-module-template.nix
#
# Template for Stackpanel app modules.
#
# This shows the standard patterns:
# - define per-app options under stackpanel.apps.\<name\>.\<module\>
# - add a module to stackpanel.appModules so it applies to every app
# - write files via stackpanel.files.entries (derivation-backed)
#
# Usage:
#   imports = [ ./modules/app-module-template.nix ];
#   stackpanel.appModules = [ config.stackpanel.modules.myModule ];
#   stackpanel.apps.myapp.myModule.enable = true;
#   # Example of consuming wrapped tooling:
#   # config.stackpanel.appsComputed.myapp.wrappedTooling.formatters
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;
in
{
  # ---------------------------------------------------------------------------
  # Option boilerplate for per-app configuration
  # ---------------------------------------------------------------------------
  options.stackpanel.modules.myModule =
    { lib, ... }:
    {
      options = {
        myModule = {
          enable = lib.mkEnableOption "example app module";

          generateFiles = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to generate module files for this app.";
          };

          # Example custom option
          message = lib.mkOption {
            type = lib.types.str;
            default = "hello from stackpanel";
            description = "Sample value used in generated files.";
          };
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Example implementation: generate a file per app
  # ---------------------------------------------------------------------------
  config = lib.mkIf cfg.enable {
    # Attach the module to every app
    stackpanel.appModules = lib.mkAfter [
      config.stackpanel.modules.myModule
    ];

    # Generate files for apps that enable the module
    stackpanel.files.enable = true;
    stackpanel.files.entries = lib.mkMerge (
      lib.mapAttrsToList (
        name: app:
        let
          appCfg =
            app.myModule or {
              enable = false;
              generateFiles = false;
            };
          appPath = app.path or "apps/${name}";
        in
        lib.optionalAttrs (appCfg.enable && appCfg.generateFiles) {
          "${appPath}/.stackpanel/${name}.txt" = {
            type = "derivation";
            drv = pkgs.writeText "${name}-stackpanel.txt" ''
              ${appCfg.message}
            '';
          };
        }
      ) (cfg.apps or { })
    );
  };
}
