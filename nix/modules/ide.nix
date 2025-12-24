# IDE integration for devenv
# Uses devenv's native `files` option for file generation
#
{
  pkgs,
  lib,
  config,
  options,
  ...
}: let
  cfg = config.stackpanel.ide;
  stackpanelCfg = config.stackpanel;
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = stackpanelCfg.dirs or { gen = ".stackpanel/gen"; };

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

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
    if cfg.vscode.existing-settings-path != null && builtins.pathExists cfg.vscode.existing-settings-path
    then builtins.fromJSON (builtins.readFile cfg.vscode.existing-settings-path)
    else {};

  # Generate terminal integration settings using shared lib
  generatedSettings = ideLib.mkVscodeSettings { inherit loaderPath; } // {
    # YAML extension settings
    "yaml.schemas" = yamlSchemas;
    "yaml.customTags" = [];
    "yaml.validate" = true;
    "yaml.completion" = true;
    "yaml.hover" = true;
  };

  # Merge settings: existing -> generated -> user overrides
  mergedSettings = existingSettings // generatedSettings // cfg.vscode.settings;

  # Generate the devshell loader script content (always devenv mode in this module)
  devshellLoaderScript = ideLib.mkDevshellLoader {
    shellMode = "devenv";
    vscode = true;
    asPackage = false;
  };

  # Generate workspace content using shared lib
  # Always include redhat.vscode-yaml for schema intellisense
  # rootPath is relative from .stackpanel/gen/ide/vscode/ to repo root
  workspaceContent = ideLib.mkWorkspaceContent {
    settings = mergedSettings;
    extraFolders = cfg.vscode.extra-folders;
    extensions = ["redhat.vscode-yaml"] ++ cfg.vscode.extensions;
    rootPath = "../../../..";
  };

in {
  options.stackpanel.ide = {
    enable = lib.mkEnableOption "IDE integration" // {
      description = "Generate IDE configuration files into .stackpanel/gen/ide/";
    };

    vscode = {
      enable = lib.mkEnableOption "VS Code integration" // {
        description = "Generate VS Code workspace and configuration files";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        description = ''
          VS Code settings to include in the generated configuration.
          These take highest priority and will override any existing or generated settings.
        '';
      };

      existing-settings-path = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to existing VS Code settings.json to merge with generated settings.

          WARNING: This creates IMPURE evaluation - the file must exist at Nix evaluation time.
        '';
      };

      output-mode = lib.mkOption {
        type = lib.types.enum ["workspace" "settingsJson"];
        default = "workspace";
        description = ''
          Where to output VS Code settings:
          - "workspace": Generate .stackpanel/gen/ide/vscode/stackpanel.code-workspace (default, safe)
          - "settingsJson": Generate .vscode/settings.json (CAUTION: may overwrite existing file)
        '';
      };

      workspace-name = lib.mkOption {
        type = lib.types.str;
        default = "stackpanel";
        description = "Name for the generated .code-workspace file (without extension)";
      };

      extra-folders = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.str);
        default = [];
        description = "Additional workspace folders to include";
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Recommended VS Code extension IDs";
      };
    };

    # Placeholders for future editors
    zed.enable = lib.mkEnableOption "Zed editor integration (not yet implemented)";
    cursor.enable = lib.mkEnableOption "Cursor editor integration (not yet implemented)";
  };

  config = lib.mkIf (stackpanelCfg.enable && cfg.enable && cfg.vscode.enable && !(stackpanelCfg.cli.enable or false)) (lib.optionalAttrs isDevenv {
    # Add hints about IDE integration
    stackpanel.motd.hints = lib.mkIf cfg.vscode.enable [
      "Open ${baseDir}/${cfg.vscode.workspace-name}.code-workspace in VS Code for integrated terminal"
    ];

    # Warn about unimplemented editors
    warnings = lib.optional cfg.zed.enable
      "stackpanel.ide.zed.enable is set but Zed integration is not yet implemented"
      ++ lib.optional cfg.cursor.enable
      "stackpanel.ide.cursor.enable is set but Cursor integration is not yet implemented";

    # Use devenv's native files option for file generation
    # NOTE: This is disabled when stackpanel.cli.enable = true (CLI handles generation)
    files = {
      # Devshell loader script (executable)
      "${baseDir}/devshell-loader.sh" = {
        text = devshellLoaderScript;
        executable = true;
      };
    }
    # Generate workspace file (default mode)
    // lib.optionalAttrs (cfg.vscode.output-mode == "workspace") {
      "${baseDir}/${cfg.vscode.workspace-name}.code-workspace".json = workspaceContent;
    }
    # Generate settings.json (explicit opt-in)
    // lib.optionalAttrs (cfg.vscode.output-mode == "settingsJson") {
      ".vscode/settings.json".json = mergedSettings;
    };
  });
}
