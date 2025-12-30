# ==============================================================================
# ide.nix
#
# IDE integration module for VS Code and other editors.
#
# This module generates IDE configuration files that integrate the stackpanel
# shell with editor terminals. For VS Code, it creates:
#   - A devshell loader script that initializes the nix environment
#   - A .code-workspace file with proper terminal integration
#   - YAML schema associations for secrets/config file intellisense
#
# Usage:
#   stackpanel.ide = {
#     enable = true;
#     vscode = {
#       enable = true;
#       workspace-name = "myproject";
#       settings = { /* custom VS Code settings */ };
#     };
#   };
#
# The generated workspace file should be opened in VS Code to get integrated
# terminal sessions that automatically load the stackpanel environment.
# ==============================================================================
{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  cfg = config.stackpanel.ide;
  stackpanelCfg = config.stackpanel;
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = stackpanelCfg.dirs or { gen = ".stackpanel/gen"; };

  # Detect if stackpanel.files is available
  hasFilesOption = options ? stackpanel.files;

  # Import the IDE lib for generating configuration
  ideLib = import ../lib/integrations/ide.nix { inherit pkgs lib; };

  # Base directory for VS Code files (in gen-dir since these are generated)
  baseDir = "${dirs.gen}/ide/vscode";

  # Loader path as VS Code sees it (with ${workspaceFolder} variable)
  loaderPath = "\${workspaceFolder}/${baseDir}/devshell-loader.sh";

  # Schema paths (relative to workspace root)
  schemasDir = "${dirs.gen}/schemas/secrets";

  # YAML schema associations for intellisense
  yamlSchemas = {
    "./${schemasDir}/config.schema.json" = ".stackpanel/secrets/config.yaml";
    "./${schemasDir}/users.schema.json" = ".stackpanel/secrets/users.yaml";
    "./${schemasDir}/app-config.schema.json" = ".stackpanel/secrets/apps/*/config.yaml";
    "./${schemasDir}/schema.schema.json" = ".stackpanel/secrets/apps/*/common.yaml";
    "./${schemasDir}/env.schema.json" = [
      ".stackpanel/secrets/apps/*/dev.yaml"
      ".stackpanel/secrets/apps/*/staging.yaml"
      ".stackpanel/secrets/apps/*/prod.yaml"
    ];
  };

  # Read existing settings if path is provided (IMPURE)
  existingSettings =
    if
      cfg.vscode.existing-settings-path != null && builtins.pathExists cfg.vscode.existing-settings-path
    then
      builtins.fromJSON (builtins.readFile cfg.vscode.existing-settings-path)
    else
      { };

  # Generate terminal integration settings using shared lib
  generatedSettings = ideLib.mkVscodeSettings { inherit loaderPath; } // {
    # YAML extension settings
    "yaml.schemas" = yamlSchemas;
    "yaml.customTags" = [ ];
    "yaml.validate" = true;
    "yaml.completion" = true;
    "yaml.hover" = true;
  };

  # Merge settings: existing -> generated -> user overrides
  mergedSettings = existingSettings // generatedSettings // cfg.vscode.settings;

  # Generate the devshell loader script content (always stackpanel mode in this module)
  devshellLoaderScript = ideLib.mkDevshellLoader {
    shellMode = "stackpanel";
    vscode = true;
    asPackage = false;
  };

  # Generate workspace content using shared lib
  # Always include redhat.vscode-yaml for schema intellisense
  # rootPath is relative from .stackpanel/gen/ide/vscode/ to repo root
  workspaceContent = ideLib.mkWorkspaceContent {
    settings = mergedSettings;
    extraFolders = cfg.vscode.extra-folders;
    extensions = [ "redhat.vscode-yaml" ] ++ cfg.vscode.extensions;
    rootPath = "../../../..";
  };

in
{
  config =
    lib.mkIf
      (stackpanelCfg.enable && cfg.enable && cfg.vscode.enable && !(stackpanelCfg.cli.enable or false))
      (
        lib.optionalAttrs hasFilesOption {
          # Add hints about IDE integration
          stackpanel.motd.hints = lib.mkIf cfg.vscode.enable [
            "Open ${baseDir}/${cfg.vscode.workspace-name}.code-workspace in VS Code for integrated terminal"
          ];

          # Warn about unimplemented editors
          warnings =
            lib.optional cfg.zed.enable "stackpanel.ide.zed.enable is set but Zed integration is not yet implemented"
            ++ lib.optional cfg.cursor.enable "stackpanel.ide.cursor.enable is set but Cursor integration is not yet implemented";

          # Use stackpanel.files for file generation
          # NOTE: This is disabled when stackpanel.cli.enable = true (CLI handles generation)
          stackpanel.files = {
            enable = true;
            files = [
              # Devshell loader script (executable)
              {
                path = "${baseDir}/devshell-loader.sh";
                drv = pkgs.writeText "devshell-loader.sh" devshellLoaderScript;
                mode = "755";
              }
            ]
            # Generate workspace file (default mode)
            ++ lib.optional (cfg.vscode.output-mode == "workspace") {
              path = "${baseDir}/${cfg.vscode.workspace-name}.code-workspace";
              drv = pkgs.writeText "${cfg.vscode.workspace-name}.code-workspace" (
                builtins.toJSON workspaceContent
              );
            }
            # Generate settings.json (explicit opt-in)
            ++ lib.optional (cfg.vscode.output-mode == "settingsJson") {
              path = ".vscode/settings.json";
              drv = pkgs.writeText "settings.json" (builtins.toJSON mergedSettings);
            };
          };
        }
      );
}
