# ==============================================================================
# ide.nix
#
# IDE integration options - VS Code, Zed, Cursor configurations.
#
# Generates IDE configuration files into .stackpanel/gen/ide/ to provide
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
# Other editors (Zed, Cursor) are placeholders for future implementation.
#
# Generated files are in .stackpanel/gen/ide/vscode/ and should be opened
# as a workspace for the best experience.
# ==============================================================================
{ lib, ... }: {
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
}
