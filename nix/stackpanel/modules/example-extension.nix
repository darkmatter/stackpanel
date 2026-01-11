# ==============================================================================
# example-extension.nix
#
# Example extension module demonstrating the extension panels feature.
#
# This module shows how to:
#   1. Register an extension with UI panels
#   2. Define panel types (status, apps grid)
#   3. Use typed fields that map to React component props
#   4. Include per-app computed data
#
# To enable, add to your stackpanel config:
#   stackpanel.example.enable = true;
#
# The extension will appear in the web UI's Extensions page.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.example or { enable = false; };

  # Example: get some computed data
  nixVersion = builtins.nixVersion or "unknown";
  systemType = builtins.currentSystem or "unknown";
in
{
  # Define options for this example extension
  options.stackpanel.example = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the example extension to demonstrate panels";
    };

    message = lib.mkOption {
      type = lib.types.str;
      default = "Hello from Stackpanel!";
      description = "A custom message to display in the panel";
    };
  };

  # Register the extension when enabled
  config = lib.mkIf (cfg.enable or false) {
    stackpanel.extensions.example = {
      name = "Example Extension";
      enabled = true;
      priority = 999; # Low priority (shows last)
      tags = [
        "example"
        "demo"
      ];

      panels = [
        # Status panel showing system info
        {
          id = "example-status";
          title = "System Information";
          description = "Shows basic system and Nix information";
          type = "PANEL_TYPE_STATUS";
          order = 1;
          fields = [
            {
              name = "metrics";
              type = "FIELD_TYPE_STRING";
              value = builtins.toJSON [
                {
                  label = "Nix Version";
                  value = nixVersion;
                  status = "ok";
                }
                {
                  label = "System";
                  value = systemType;
                  status = "ok";
                }
                {
                  label = "Custom Message";
                  value = cfg.message or "Hello!";
                  status = "ok";
                }
                {
                  label = "Extension Status";
                  value = "Active";
                  status = "ok";
                }
              ];
            }
          ];
        }

        # Apps grid showing all configured apps
        {
          id = "example-apps";
          title = "All Applications";
          description = "Shows all apps in the stackpanel configuration";
          type = "PANEL_TYPE_APPS_GRID";
          order = 2;
          fields = [
            {
              name = "columns";
              type = "FIELD_TYPE_COLUMNS";
              value = builtins.toJSON [
                "name"
                "path"
                "port"
                "config"
              ];
            }
          ];
        }
      ];

      # Include all apps as "extension apps" for demonstration
      apps = lib.mapAttrs (name: app: {
        enabled = true;
        config = {
          path = app.path or "";
          hasUrl = if (app.url or null) != null then "yes" else "no";
        };
      }) (config.stackpanel.apps or { });
    };
  };
}
