# ==============================================================================
# ide.nix
#
# IDE integration options - VS Code, Zed, Cursor configurations.
#
# Generates IDE configuration files into .stack/gen/ide/ to provide
# a consistent development experience with Nix-managed settings.
#
# VS Code options:
#   - enable: Generate VS Code configuration
#   - settings: VS Code settings to include
#   - existing-settings-path: Merge with existing settings.json (impure)
#   - output-mode: "workspace" or "settingsJson"
#   - workspace-name: Name for the .code-workspace file
#   - extra-folders: Additional workspace folders
#   - extensions: Recommended extension IDs
#
# Zed options:
#   - enable: Generate Zed configuration
#   - settings: Zed settings to include
#   - existing-settings-path: Merge with existing settings.json (impure)
#   - output-mode: "generated" or "dotZed"
#   - extensions: Recommended extension IDs
#
# Generated files are in .stack/gen/ide/{editor}/ and should be symlinked
# or opened as appropriate for each editor.
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.ide = {
    enable = lib.mkEnableOption "IDE integration" // {
      description = "Generate IDE configuration files into .stack/gen/ide/";
    };

    vscode = {
      enable = lib.mkEnableOption "VS Code integration" // {
        description = "Generate VS Code workspace and configuration files";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
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
        type = lib.types.enum [
          "workspace"
          "settingsJson"
        ];
        default = "workspace";
        description = ''
          Where to output VS Code settings:
          - "workspace": Generate .stack/gen/ide/vscode/stackpanel.code-workspace (default, safe)
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
        default = [ ];
        description = "Additional workspace folders to include";
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Recommended VS Code extension IDs";
      };
    };

    zed = {
      enable = lib.mkEnableOption "Zed editor integration" // {
        description = "Generate Zed configuration files";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Zed settings to include in the generated configuration.
          These take highest priority and will override any existing or generated settings.
        '';
      };

      existing-settings-path = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to existing Zed settings.json to merge with generated settings.

          WARNING: This creates IMPURE evaluation - the file must exist at Nix evaluation time.
        '';
      };

      output-mode = lib.mkOption {
        type = lib.types.enum [
          "generated"
          "dotZed"
        ];
        default = "generated";
        description = ''
          Where to output Zed settings:
          - "generated": Generate to .stack/gen/zed/ (default, safe) - requires manual symlink
          - "dotZed": Generate to .zed/settings.json (CAUTION: may overwrite existing file)
        '';
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Recommended Zed extension IDs";
      };

      tasks = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        default = [ ];
        description = ''
          Zed tasks to include in the generated tasks.json.
          Each task is an attrset with label, command, args, etc.
        '';
        example = [
          {
            label = "dev";
            command = "bun";
            args = [
              "run"
              "dev"
            ];
          }
        ];
      };
    };

    # Placeholder for future editors
    cursor.enable = lib.mkEnableOption "Cursor editor integration (not yet implemented)";
  };
}
