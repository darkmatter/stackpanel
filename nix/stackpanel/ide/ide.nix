# ==============================================================================
# ide.nix
#
# IDE integration module for VS Code and other editors.
#
# This module generates IDE configuration files that integrate the stackpanel
# shell with editor terminals. For VS Code, it creates:
#   - A devshell loader script that initializes the nix environment
#   - A .code-workspace file with proper terminal integration
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
  ideLib = import ../lib/ide.nix { inherit pkgs lib; };

  # Helper to create a pretty-printed JSON file
  mkPrettyJson =
    name: content:
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "json" ];
        json = builtins.toJSON content;
      }
      ''
        jq . "$jsonPath" > $out
      '';

  # Base directory for VS Code files (in gen-dir since these are generated)
  baseDir = "${dirs.gen}/vscode";

  # Loader path as VS Code sees it (with ${workspaceFolder} variable)
  loaderPath = "\${workspaceFolder}/${baseDir}/devshell-loader.sh";

  # Read existing settings if path is provided (IMPURE)
  existingSettings =
    if
      cfg.vscode.existing-settings-path != null && builtins.pathExists cfg.vscode.existing-settings-path
    then
      builtins.fromJSON (builtins.readFile cfg.vscode.existing-settings-path)
    else
      { };

  # Generate terminal integration settings using shared lib
  generatedSettings = ideLib.mkVscodeSettings { inherit loaderPath; };

  # Merge settings: existing -> generated -> user overrides
  mergedSettings = existingSettings // generatedSettings // cfg.vscode.settings;

  # Generate the devshell loader script content (always stackpanel mode in this module)
  devshellLoaderScript = ideLib.mkDevshellLoader {
    shellMode = "stackpanel";
    vscode = true;
    asPackage = false;
  };

  workspaceName = stackpanelCfg.name or cfg.vscode.workspace-name or "stackpanel";

  # Generate workspace content using shared lib
  # rootPath is relative from .stackpanel/gen/vscode/ to repo root
  workspaceContent = ideLib.mkWorkspaceContent {
    settings = mergedSettings;
    extraFolders = cfg.vscode.extra-folders;
    extensions = cfg.vscode.extensions;
    rootPath = "../../..";
  };
in
{
  config = lib.mkIf (stackpanelCfg.enable && cfg.enable && cfg.vscode.enable) (
    lib.optionalAttrs hasFilesOption {
      # Add hints about IDE integration
      stackpanel.motd.hints = lib.mkIf cfg.vscode.enable [
        "Open ${baseDir}/${workspaceName}.code-workspace in VS Code for integrated terminal"
      ];

      # Use stackpanel.files for file generation
      # NOTE: This is disabled when stackpanel.cli.enable = true (CLI handles generation)
      stackpanel.files.enable = true;
      stackpanel.files.entries = {
        "${baseDir}/devshell-loader.sh" = {
          type = "derivation";
          drv = pkgs.writeText "devshell-loader.sh" devshellLoaderScript;
          mode = "0755";
          source = "ide";
          description = "Shell script that loads the Nix devshell environment for VS Code terminal";
        };
      }
      // lib.optionalAttrs (cfg.vscode.output-mode == "workspace") {
        # Generate workspace file (default mode)
        "${baseDir}/${cfg.vscode.workspace-name}.code-workspace" = {
          type = "derivation";
          drv = mkPrettyJson "${cfg.vscode.workspace-name}.code-workspace" workspaceContent;
          source = "ide";
          description = "VS Code workspace configuration with integrated terminal settings";
        };
      }
      // lib.optionalAttrs (cfg.vscode.output-mode == "settingsJson") {
        # Generate settings.json (explicit opt-in)
        ".vscode/settings.json" = {
          type = "derivation";
          drv = mkPrettyJson "settings.json" mergedSettings;
          source = "ide";
          description = "VS Code settings with terminal integration";
        };
      };
    }
  );
}
