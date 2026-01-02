# ==============================================================================
# devshell.nix
#
# Devshell configuration options - packages, hooks, commands, and files.
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
#   - commands: Named commands with exec, runtimeInputs, and env
#
# Files options (stackpanel.files):
#   - enable: Enable file generation
#   - exeFilename: Name of the writer executable
#   - files: List of { path, drv, mode } for files to generate
#
# This module is adapter-agnostic; the actual shell creation happens in
# the devenv or flake adapter modules.
# ==============================================================================
{ lib, config, ... }:
let
  types = lib.types;
in
{
  # ----------------------------------------------------------------------------
  # Top-level packages (preferred API)
  # ----------------------------------------------------------------------------
  options.stackpanel.packages = lib.mkOption {
    type = types.listOf types.package;
    default = [];
    description = "Packages to include in the devshell. Preferred over devshell.packages.";
  };

  # ----------------------------------------------------------------------------
  # Devshell
  # ----------------------------------------------------------------------------
  options.stackpanel.devshell = {
    packages = lib.mkOption { type = types.listOf types.package; default = []; };
    nativeBuildInputs = lib.mkOption { type = types.listOf types.package; default = []; };
    buildInputs = lib.mkOption { type = types.listOf types.package; default = []; };

    env = lib.mkOption { type = types.attrsOf types.str; default = {}; };

    path.prepend = lib.mkOption { type = types.listOf types.str; default = []; };
    path.append  = lib.mkOption { type = types.listOf types.str; default = []; };

    hooks.before = lib.mkOption { type = types.listOf types.str; default = []; };
    hooks.main   = lib.mkOption { type = types.listOf types.str; default = []; };
    hooks.after  = lib.mkOption { type = types.listOf types.str; default = []; };

    # commands: name -> { exec = "..." ; packages = [...] ; env = {...}; }
    commands = lib.mkOption {
      type = types.attrsOf (types.submodule ({ ... }: {
        options = {
          exec = lib.mkOption { type = types.str; };
          runtimeInputs = lib.mkOption { type = types.listOf types.package; default = []; };
          env = lib.mkOption { type = types.attrsOf types.str; default = {}; };
        };
      }));
      default = {};
    };

    _commandPkgs = lib.mkOption {
      description = "Internal: Packages for devshell commands.";
      type = lib.types.listOf lib.types.package;
      default = [];
      internal = true;
    };
  };

  # ----------------------------------------------------------------------------
  # Files
  # ----------------------------------------------------------------------------
  options.stackpanel.files = {
    enable = lib.mkEnableOption "file generation" // { default = true; };

    entries = lib.mkOption {
      description = ''
        Files to generate into the repo. Keys are file paths relative to repo root.

        Example:
          stackpanel.files.entries.".github/workflows/ci.yml" = {
            type = "text";
            text = "name: CI\n...";
          };
          stackpanel.files.entries."scripts/deploy.sh" = {
            type = "derivation";
            drv = pkgs.writeScript "deploy" "#!/bin/bash\n...";
            mode = "0755";
          };
      '';
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = lib.mkEnableOption "Generate this file" // { default = true; };

          type = lib.mkOption {
            type = types.enum [ "text" "derivation" ];
            default = "text";
            description = "Type of file content: 'text' for inline text, 'derivation' for a derivation.";
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

          mode = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional chmod mode (e.g. '0644', '0755').";
            example = "0755";
          };
        };
      }));
      default = {};
    };
  };

  # ----------------------------------------------------------------------------
  # Config: merge top-level packages into devshell.packages
  # ----------------------------------------------------------------------------
  config = {
    stackpanel.devshell.packages = config.stackpanel.packages;
  };
}