# ==============================================================================
# ide.nix
#
# IDE integration module for VS Code, Zed, and other editors.
#
# This module generates IDE configuration files that integrate the stackpanel
# shell with editor terminals.
#
# For VS Code, it creates:
#   - A devshell loader script that initializes the nix environment
#   - A .code-workspace file with proper terminal integration
#
# For Zed, it creates:
#   - A devshell loader script that initializes the nix environment
#   - A settings.json file with terminal integration
#   - Optionally, a tasks.json file with custom tasks
#
# Usage:
#   stackpanel.ide = {
#     enable = true;
#     vscode = {
#       enable = true;
#       workspace-name = "myproject";
#       settings = { /* custom VS Code settings */ };
#     };
#     zed = {
#       enable = true;
#       settings = { /* custom Zed settings */ };
#     };
#   };
#
# The generated files should be opened/symlinked as appropriate for each editor.
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
  dirs = stackpanelCfg.dirs or { gen = ".stack/gen"; };

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

  # ===========================================================================
  # VS Code Configuration
  # ===========================================================================

  # Base directory for VS Code files (in gen-dir since these are generated)
  vscodeBaseDir = "${dirs.gen}/vscode";

  # Loader path as VS Code sees it (with ${workspaceFolder} variable)
  vscodeLoaderPath = "\${workspaceFolder}/${vscodeBaseDir}/devshell-loader.sh";

  # Read existing VS Code settings if path is provided (IMPURE)
  vscodeExistingSettings =
    if
      cfg.vscode.existing-settings-path != null && builtins.pathExists cfg.vscode.existing-settings-path
    then
      builtins.fromJSON (builtins.readFile cfg.vscode.existing-settings-path)
    else
      { };

  # Generate VS Code terminal integration settings using shared lib
  vscodeGeneratedSettings = ideLib.mkVscodeSettings { loaderPath = vscodeLoaderPath; };

  # Merge VS Code settings: existing -> generated -> user overrides
  vscodeMergedSettings = vscodeExistingSettings // vscodeGeneratedSettings // cfg.vscode.settings;

  # Generate the devshell loader script content (always stackpanel mode in this module)
  devshellLoaderScript = ideLib.mkDevshellLoader {
    shellMode = "stackpanel";
    vscode = true;
    asPackage = false;
  };

  workspaceName = stackpanelCfg.name or cfg.vscode.workspace-name or "stackpanel";

  # Generate workspace content using shared lib
  # rootPath is relative from .stack/gen/vscode/ to repo root
  workspaceContent = ideLib.mkWorkspaceContent {
    settings = vscodeMergedSettings;
    extraFolders = cfg.vscode.extra-folders;
    extensions = cfg.vscode.extensions;
    rootPath = "../../..";
  };

  # ===========================================================================
  # Zed Configuration
  # ===========================================================================

  # Base directory for Zed files (in gen-dir since these are generated)
  zedBaseDir = "${dirs.gen}/zed";

  # Loader path for Zed (relative to project root)
  zedLoaderPath = "${zedBaseDir}/devshell-loader.sh";

  # Read existing Zed settings if path is provided (IMPURE)
  zedExistingSettings =
    if cfg.zed.existing-settings-path != null && builtins.pathExists cfg.zed.existing-settings-path then
      builtins.fromJSON (builtins.readFile cfg.zed.existing-settings-path)
    else
      { };

  # Generate Zed terminal integration settings using shared lib
  zedGeneratedSettings = ideLib.mkZedSettings { loaderPath = zedLoaderPath; };

  # Merge Zed settings: existing -> generated -> user overrides
  zedMergedSettings = ideLib.mkZedLocalSettings {
    settings = zedExistingSettings // cfg.zed.settings;
    terminalSettings = zedGeneratedSettings;
  };

  # Generate Zed tasks content if tasks are defined
  zedTasksContent = ideLib.mkZedTasksContent {
    tasks = cfg.zed.tasks;
    loaderPath = zedLoaderPath;
  };
in
{
  config = lib.mkIf (stackpanelCfg.enable && cfg.enable) (
    lib.optionalAttrs hasFilesOption {
      # Use stackpanel.files for file generation
      # NOTE: This is disabled when stackpanel.cli.enable = true (CLI handles generation)
      stackpanel.files.enable = true;

      # Add hints about IDE integration
      stackpanel.motd.hints =
        lib.optional cfg.vscode.enable "Open ${vscodeBaseDir}/${workspaceName}.code-workspace in VS Code for integrated terminal"
        ++ lib.optional cfg.zed.enable "Zed: symlink .zed -> ${zedBaseDir} or open project normally";

      # ===========================================================================
      # VS Code files
      # ===========================================================================
      stackpanel.files.entries =
        lib.optionalAttrs cfg.vscode.enable {
          "${vscodeBaseDir}/devshell-loader.sh" = {
            type = "derivation";
            drv = pkgs.writeText "devshell-loader.sh" devshellLoaderScript;
            mode = "0755";
            source = "ide";
            description = "Shell script that loads the Nix devshell environment for VS Code terminal";
          };
        }
        // lib.optionalAttrs (cfg.vscode.enable && cfg.vscode.output-mode == "workspace") {
          # Generate workspace file (default mode)
          "${vscodeBaseDir}/${cfg.vscode.workspace-name}.code-workspace" = {
            type = "derivation";
            drv = mkPrettyJson "${cfg.vscode.workspace-name}.code-workspace" workspaceContent;
            source = "ide";
            description = "VS Code workspace configuration with integrated terminal settings";
          };
        }
        // lib.optionalAttrs (cfg.vscode.enable && cfg.vscode.output-mode == "settingsJson") {
          # Generate settings.json (explicit opt-in)
          ".vscode/settings.json" = {
            type = "derivation";
            drv = mkPrettyJson "settings.json" vscodeMergedSettings;
            source = "ide";
            description = "VS Code settings with terminal integration";
          };
        }
        # ===========================================================================
        # Zed files
        # ===========================================================================
        // lib.optionalAttrs cfg.zed.enable {
          "${zedBaseDir}/devshell-loader.sh" = {
            type = "derivation";
            drv = pkgs.writeText "devshell-loader.sh" devshellLoaderScript;
            mode = "0755";
            source = "ide";
            description = "Shell script that loads the Nix devshell environment for Zed terminal";
          };
        }
        // lib.optionalAttrs (cfg.zed.enable && cfg.zed.output-mode == "generated") {
          # Generate settings.json to gen dir (default mode, safe)
          "${zedBaseDir}/settings.json" = {
            type = "derivation";
            drv = mkPrettyJson "zed-settings.json" zedMergedSettings;
            source = "ide";
            description = "Zed settings with terminal integration";
          };
        }
        // lib.optionalAttrs (cfg.zed.enable && cfg.zed.output-mode == "dotZed") {
          # Generate settings.json directly to .zed/ (explicit opt-in)
          ".zed/settings.json" = {
            type = "derivation";
            drv = mkPrettyJson "zed-settings.json" zedMergedSettings;
            source = "ide";
            description = "Zed settings with terminal integration";
          };
        }
        // lib.optionalAttrs (cfg.zed.enable && cfg.zed.tasks != [ ]) {
          # Generate tasks.json if tasks are defined
          "${if cfg.zed.output-mode == "dotZed" then ".zed" else zedBaseDir}/tasks.json" = {
            type = "derivation";
            drv = mkPrettyJson "zed-tasks.json" zedTasksContent;
            source = "ide";
            description = "Zed tasks configuration";
          };
        };
    }
  );
}
