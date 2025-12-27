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
{ lib, ... }:
let
  types = lib.types;
in
{
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
    enable = lib.mkEnableOption "Generate arbitrary files into the repo";

    # command name
    exeFilename = lib.mkOption {
      type = types.str;
      default = "write-files";
      description = "Name of the generated writer executable.";
    };

    # where to write; defaults to your core behavior
    rootVar = lib.mkOption {
      type = types.str;
      default = "STACKPANEL_ROOT";
      description = "Environment variable that points at the repo root.";
    };

    files = lib.mkOption {
      description = "List of files to write (path relative to repo root) + derivation with contents.";
      type = types.listOf (types.submodule ({ ... }: {
        options = {
          path = lib.mkOption {
            type = types.str;
            description = "File path relative to repo root.";
            example = ".github/workflows/ci.yml";
          };
          drv = lib.mkOption {
            type = types.package;
            description = "Derivation whose outPath is a file containing the desired content.";
          };
          mode = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional chmod mode (e.g. 0644, 0755).";
          };
        };
      }));
      default = [];
    };
  };
}