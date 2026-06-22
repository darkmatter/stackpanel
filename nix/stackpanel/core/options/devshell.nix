# ==============================================================================
# devshell.nix
#
# Devshell configuration options - packages, hooks, env, and PATH.
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
# Files options are defined by the top-level files module in nix/stackpanel/files/default.nix.
#
# This module is adapter-agnostic; the actual shell creation happens in
# the devenv or flake adapter modules.
#
# NOTE: This module uses db.extend.none because devshell options are pure Nix
# (no proto schema). The mkOpt pattern still applies for consistency.
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  ...
}:
let
  inherit (lib) types;
  db = import ../../db { inherit lib; };
  hasPkgs = pkgs != null;

  # Resolve a package name string to a package from pkgs
  resolvePackage =
    name:
    let
      parts = lib.splitString "." name;
      resolved = lib.attrByPath parts null pkgs;
    in
    if resolved != null then resolved else null;

  # Type that accepts either a package or a string (package name)
  packageOrString = types.either types.package types.str;
in
{
  # ----------------------------------------------------------------------------
  # Top-level packages (preferred API)
  # Accepts either actual packages or string package names (resolved from nixpkgs)
  # ----------------------------------------------------------------------------
  options.stackpanel.packages = lib.mkOption {
    type = types.listOf packageOrString;
    default = [ ];
    description = ''
      Packages to include in the devshell.

      Can be either:
      - Actual Nix packages (e.g., pkgs.git)
      - String package names (e.g., "git") - resolved from nixpkgs

      String packages are resolved via nixpkgs attribute paths, supporting
      nested paths like "nodePackages.typescript".
    '';
    example = lib.literalExpression ''
      [
        pkgs.git
        "ripgrep"
        "nodePackages.typescript"
      ]
    '';
  };

  # Resolved packages (internal) - converts strings to packages
  options.stackpanel.packagesResolved = lib.mkOption {
    type = types.listOf types.package;
    default = [ ];
    internal = true;
    description = "Internal: packages with strings resolved to actual packages.";
  };

  # ----------------------------------------------------------------------------
  # Devshell - pure Nix options (no proto schema)
  # ----------------------------------------------------------------------------
  options.stackpanel.devshell = db.mkOpt db.extend.none {
    packages = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Packages to add to the devshell (convenience wrapper over nativeBuildInputs + buildInputs).";
      example = lib.literalExpression ''
        [
          "git"
          "ripgrep"
          "nodePackages.typescript"
        ]
      '';
    };
    nativeBuildInputs = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Native build inputs for the devshell (tools needed to build, not necessarily at runtime).";
      example = lib.literalExpression "[ pkgs.pkg-config pkgs.cmake ]";
    };
    buildInputs = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Runtime libraries and packages exposed to builds that run inside the devshell.";
      example = lib.literalExpression "[ pkgs.openssl pkgs.zlib ]";
    };

    env = lib.mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Environment variables to set in the devshell.";
      example = {
        NODE_ENV = "development";
        MY_SERVICE_URL = "http://localhost:8080";
      };
    };

    path.prepend = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Directories to prepend to PATH in the devshell.";
      example = [ "./node_modules/.bin" ];
    };
    path.append = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Directories to append to PATH in the devshell.";
      example = [ ];
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

    # Clean environment mode - start with a minimal environment
    clean.enable = lib.mkEnableOption "clean environment mode" // {
      default = false;
    };

    clean.impure = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to use --impure flag when entering the devshell. When set to false,
        the following will not be available:

        - Reading any files that aren't checked into your git repository
        - Accessing environment variables and system state

        You should try to keep this set to false - it will result in much more
        reproducible builds. If using devenv, this must be set to true.
      '';
      example = false;
    };

    clean.keep = lib.mkOption {
      type = types.listOf types.str;
      default = [
        # Identity & shell
        "HOME"
        "USER"
        "LOGNAME"
        "SHELL"
        "TMPDIR"
        # Terminal functionality
        "TERM"
        "COLORTERM"
        "TERM_PROGRAM"
        "TERM_PROGRAM_VERSION"
        # Locale
        "LANG"
        "LC_ALL"
        "LC_CTYPE"
        # Authentication
        "SSH_AUTH_SOCK"
        "SSH_SOCKET_DIR"
        "GPG_AGENT_INFO"
        "GNUPGHOME"
        # Editor preferences
        "EDITOR"
        "VISUAL"
        "PAGER"
        # macOS specific
        "__CF_USER_TEXT_ENCODING"
        "COMMAND_MODE"
      ];
      description = ''
        Environment variables to preserve when clean.enable is true.
        These variables are passed through from the parent environment. Use this to
        incrementally improve the reproducibility of your devshell. Running `env` will
        show you what you currently have set.

        Use `nix develop --ignore-environment --impure` with `--keep` flags to simulate
        the effects of setting these variables in your devshell.
      '';
      example = [
        "HOME"
        "USER"
        "SSH_AUTH_SOCK"
        "DISPLAY"
      ];
    };
    # @TODO: These extras should be `clean.keep<Extra>.enable` and set them for you.
    clean.keepGui = lib.mkOption {
      type = types.listOf types.str;
      default = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
        "XDG_RUNTIME_DIR"
        "DBUS_SESSION_BUS_ADDRESS"
      ];
      description = ''
        Additional environment variables to keep for GUI applications.
        These are NOT included by default. Add them to clean.keep if needed:

          stackpanel.devshell.clean.keep = config.stackpanel.devshell.clean.keep
            ++ config.stackpanel.devshell.clean.keepGui;
      '';
      example = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
      ];
    };

    clean.keepWarp = lib.mkOption {
      type = types.listOf types.str;
      default = [
        "WARP_HONOR_PS1"
        "WARP_IS_LOCAL_SHELL_SESSION"
        "WARP_USE_SSH_WRAPPER"
      ];
      description = ''
        Environment variables for Warp terminal features.
        Add to clean.keep if using Warp terminal.
      '';
      example = [
        "WARP_HONOR_PS1"
        "WARP_IS_LOCAL_SHELL_SESSION"
      ];
    };

    clean.keepFzf = lib.mkOption {
      type = types.listOf types.str;
      default = [
        "FZF_DEFAULT_COMMAND"
        "FZF_DEFAULT_OPTS"
        "FZF_CTRL_T_COMMAND"
        "FZF_ALT_C_COMMAND"
      ];
      description = ''
        Environment variables for fzf configuration.
        Add to clean.keep if you want to preserve your fzf settings.
      '';
      example = [
        "FZF_DEFAULT_COMMAND"
        "FZF_DEFAULT_OPTS"
      ];
    };

    clean.keepXdg = lib.mkOption {
      type = types.listOf types.str;
      default = [
        "XDG_CACHE_HOME"
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
      ];
      description = ''
        XDG base directory environment variables (often set by home-manager).
        Add to clean.keep if you want to preserve these paths.
      '';
      example = [
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
      ];
    };

    clean.keepDirenv = lib.mkOption {
      type = types.listOf types.str;
      default = [
        "DIRENV_DIR"
        "DIRENV_FILE"
      ];
      description = ''
        Direnv state variables. Only needed if using direnv inside the clean shell.
      '';
      example = [
        "DIRENV_DIR"
        "DIRENV_FILE"
      ];
    };

    hooks.before = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Shell commands to run early when entering the devshell (before other setup).";
      example = [
        "echo 'Preparing dev environment...'"
      ];
    };
    hooks.main = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Main shell initialization commands (e.g. starting services or printing hints).";
      example = [
        "echo 'Welcome to the devshell for my-project'"
      ];
    };
    hooks.after = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Commands to run after the main devshell setup (e.g. final PATH tweaks).";
      example = [ ];
    };
    timing = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        If true, timing information will be printed during hook execution.
      '';
      example = true;
    };

    # Internal: Serializable script definitions for CLI/TUI access
    _commandsSerializable = lib.mkOption {
      description = "Internal: Serializable script definitions for CLI access.";
      type = types.attrsOf (
        types.submodule {
            options = {
            name = lib.mkOption {
              type = types.str;
              description = "Command name exposed to the CLI/TUI command list.";
              example = "dev";
            };
            exec = lib.mkOption {
              type = types.str;
              description = "Shell command executed when the serialized command is invoked.";
              example = "bun run dev";
            };
            description = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional help text shown next to the command in CLI/TUI command lists.";
              example = "Start the web dev server";
            };
            env = lib.mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "Environment variables applied when running this command.";
              example = { NODE_ENV = "development"; };
            };
          };
        }
      );
      default = { };
      internal = true;
    };
  };

  # ----------------------------------------------------------------------------
  # Config: resolve string packages and merge into devshell.packages
  # ----------------------------------------------------------------------------
  config = lib.mkIf hasPkgs {
    # Resolve string package names to actual packages
    stackpanel.packagesResolved =
      let
        resolveItem = item: if builtins.isString item then resolvePackage item else item;
        resolved = map resolveItem config.stackpanel.packages;
      in
      lib.filter (p: p != null) resolved;

    # Use resolved packages for the devshell
    stackpanel.devshell.packages = config.stackpanel.packagesResolved;
  };
}
