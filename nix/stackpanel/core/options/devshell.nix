# ==============================================================================
# devshell.nix
#
# Devshell configuration options - packages, hooks, and files.
#
# Central configuration for the development shell environment. These options
# are translated to devenv/nix-shell configuration by adapter modules.
#
# Devshell options:
#   - packages: List of packages to include in the shell
#   - nativeBuildInputs/buildInputs: Standard Nix build inputs
#   - env: Environment variables to set
#   - path.prepend/append: Modify PATH
#   - hooks.before/main/after: Shell initialization hooks (ordered)
#
# Scripts are defined via stackpanel.scripts (see devshell/scripts.nix).
#
# Files options (stackpanel.files):
#   - enable: Enable file generation
#   - entries: Attrset of files to generate
#
# This module is adapter-agnostic; the actual shell creation happens in
# the devenv or flake adapter modules.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  types = lib.types;
in
{
  # ----------------------------------------------------------------------------
  # Top-level packages (preferred API)
  # ----------------------------------------------------------------------------
  options.stackpanel.packages = lib.mkOption {
    type = types.listOf types.package;
    default = [ ];
    description = "Packages to include in the devshell. Preferred over devshell.packages.";
  };

  # ----------------------------------------------------------------------------
  # Devshell
  # ----------------------------------------------------------------------------
  options.stackpanel.devshell = {
    packages = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
    };
    nativeBuildInputs = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
    };
    buildInputs = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
    };

    env = lib.mkOption {
      type = types.attrsOf types.str;
      default = { };
    };

    path.prepend = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    path.append = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    # Clean up conflicting aliases when entering shell
    clean.aliases = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of shell aliases to unset when entering the devshell.
        Use this if you have aliases that conflict with stackpanel scripts (e.g., "dev").
      '';
      example = [
        "dev"
        "start"
      ];
    };

    hooks.before = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    hooks.main = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    hooks.after = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    # Internal: Serializable script definitions for CLI/TUI access
    _commandsSerializable = lib.mkOption {
      description = "Internal: Serializable script definitions for CLI access.";
      type = types.attrsOf (
        types.submodule {
          options = {
            name = lib.mkOption { type = types.str; };
            exec = lib.mkOption { type = types.str; };
            description = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            env = lib.mkOption {
              type = types.attrsOf types.str;
              default = { };
            };
          };
        }
      );
      default = { };
      internal = true;
    };
  };

  # ----------------------------------------------------------------------------
  # Files
  # ----------------------------------------------------------------------------
  options.stackpanel.files = {
    enable = lib.mkEnableOption "file generation" // {
      default = true;
    };

    entries = lib.mkOption {
      description = ''
        Files to generate into the repo. Keys are file paths relative to repo root.

        Example:
          stackpanel.files.entries.".github/workflows/ci.yml" = `\{
            type = "text";
            text = "name: CI\n...";
          \};
          stackpanel.files.entries."scripts/deploy.sh" = \{
            type = "derivation";
            drv = pkgs.writeScript "deploy" "#!/bin/bash\n...";
            mode = "0755";
          \};
      '';
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              enable = lib.mkEnableOption "Generate this file" // {
                default = true;
              };

              type = lib.mkOption {
                type = types.enum [
                  "text"
                  "derivation"
                  "symlink"
                ];
                default = "text";
                description = ''
                  Type of file content:
                  - 'text': inline text content
                  - 'derivation': copy from a derivation
                  - 'symlink': create a symbolic link
                '';
              };

              text = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Text content for the file (when type = 'text').";
              };

              drv = lib.mkOption {
                type = types.nullOr types.package;
                default = null;
                description = "Derivation whose outPath contains the file content (when type = 'derivation').";
              };

              target = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Symlink target path (when type = 'symlink'). Can be absolute (Nix store) or relative.";
                example = "/nix/store/abc123-task/bin/task";
              };

              mode = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Optional chmod mode (e.g. '0644', '0755').";
                example = "0755";
              };

              source = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Module or component that generated this file (for UI display).";
                example = "ide.nix";
              };

              description = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Human-readable description of the file's purpose.";
                example = "VS Code workspace configuration";
              };
            };
          }
        )
      );
      default = { };
    };
  };

  # ----------------------------------------------------------------------------
  # Config: merge top-level packages into devshell.packages
  # ----------------------------------------------------------------------------
  config = {
    stackpanel.devshell.packages = config.stackpanel.packages;
  };
}
