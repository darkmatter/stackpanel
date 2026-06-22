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
#   - output-mode: "generated", "symlink", or "dotZed"
#   - extensions: Recommended extension IDs
#
# Generated files are in .stack/gen/ide/{editor}/ and should be symlinked
# or opened as appropriate for each editor.
#
# Example:
#   stackpanel.ide = {
#     enable = true;
#     vscode.enable = true;
#     zed.enable = true;
#   };
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.ide = {
    enable = lib.mkEnableOption "IDE integration" // {
      description = ''
        Enable generated editor integration for this workspace.
        Turn on an editor-specific child option, such as
        `stackpanel.ide.vscode.enable` or `stackpanel.ide.zed.enable`, to emit
        concrete VS Code or Zed files under `.stack/gen/ide/` unless that
        editor's output mode writes directly to its dot-directory.
      '';
      example = true;
    };

    vscode = {
      enable = lib.mkEnableOption "VS Code integration" // {
        description = ''
          Generate VS Code workspace/configuration files wired to the
          Stackpanel devshell. By default this writes a safe
          `.stack/gen/ide/vscode/<workspace-name>.code-workspace` file.
        '';
        example = true;
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          VS Code settings to include in the generated configuration.
          These take highest priority and will override any existing or generated settings.
        '';
        example = {
          "editor.formatOnSave" = true;
          "terminal.integrated.defaultProfile.osx" = "stackpanel";
          "nix.enableLanguageServer" = true;
        };
      };

      existing-settings-path = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to existing VS Code settings.json to merge with generated settings.

          WARNING: This creates IMPURE evaluation - the file must exist at Nix evaluation time.
        '';
        example = lib.literalExpression "./.vscode/settings.json";
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
        example = "workspace";
      };

      workspace-name = lib.mkOption {
        type = lib.types.str;
        default = "stackpanel";
        description = ''
          Base filename for the generated VS Code workspace, without the
          `.code-workspace` extension. Only used when `output-mode = "workspace"`.
        '';
        example = "my-monorepo";
      };

      extra-folders = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.str);
        default = [ ];
        description = ''
          Additional folders to include in the generated `.code-workspace` file.
          Each entry is passed through as a VS Code workspace folder object.
        '';
        example = [
          {
            name = "docs";
            path = "./apps/docs";
          }
          {
            name = "infra";
            path = "./packages/infra";
          }
        ];
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          VS Code extension identifiers to include in workspace recommendations.
          These are suggestions for users opening the generated workspace, not
          packages installed into the devshell.
        '';
        example = [
          "jnoortheen.nix-ide"
          "mkhl.direnv"
          "bradlc.vscode-tailwindcss"
        ];
      };
    };

    zed = {
      enable = lib.mkEnableOption "Zed editor integration" // {
        description = ''
          Generate Zed settings, tasks, and extension recommendations wired to
          the Stackpanel workspace. The default output stays under
          `.stack/gen/ide/zed/`; use `output-mode = "dotZed"` only when this
          module should own `.zed/settings.json`.
        '';
        example = true;
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Zed settings to include in the generated configuration.
          These take highest priority and will override any existing or generated settings.
        '';
        example = {
          format_on_save = "on";
          terminal = {
            shell = "system";
          };
          languages = {
            Nix = {
              language_servers = [ "nil" ];
            };
          };
        };
      };

      existing-settings-path = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to existing Zed settings.json to merge with generated settings.

          WARNING: This creates IMPURE evaluation - the file must exist at Nix evaluation time.
        '';
        example = lib.literalExpression "./.zed/settings.json";
      };

      output-mode = lib.mkOption {
        type = lib.types.enum [
          "generated"
          "symlink"
          "dotZed"
        ];
        default = "generated";
        description = ''
          Where to output Zed settings:
          - "generated": Generate to .stack/gen/zed/ (default, safe) - requires manual symlink
          - "symlink": Generate to .stack/gen/zed/ and symlink .zed/settings.json to it
            (content stays in the gitignored gen dir, Zed picks it up automatically)
          - "dotZed": Generate a real file at .zed/settings.json (CAUTION: may overwrite existing file)
        '';
        example = "symlink";
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Zed extension identifiers to include in generated extension
          recommendations. These are editor extension IDs, not Nix packages.
        '';
        example = [
          "nix"
          "toml"
          "tailwindcss"
        ];
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
