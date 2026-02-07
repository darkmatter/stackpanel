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
  types = lib.types;
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

    # Clean environment mode - start with a minimal environment
    clean.enable = lib.mkEnableOption "clean environment mode" // {
      default = false;
    };

    clean.impure = lib.mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to use --impure flag when entering the devshell.

        --impure allows Nix to access environment variables and system state,
        but prevents effective caching between runs.

        Set to false if you want better caching and your devshell doesn't
        need access to parent environment state.
      '';
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
        These variables are passed through from the parent environment.

        Use `nix develop --ignore-environment --impure` with `--keep` flags
        for each variable in this list, or use the generated wrapper script.
      '';
      example = [
        "HOME"
        "USER"
        "SSH_AUTH_SOCK"
        "DISPLAY"
      ];
    };

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
  # Files - pure Nix options (no proto schema)
  # ----------------------------------------------------------------------------
  options.stackpanel.files = db.mkOpt db.extend.none {
    enable = lib.mkEnableOption "file generation" // {
      default = true;
    };

    entries = lib.mkOption {
      description = ''
        Files to generate into the repo. Keys are file paths relative to repo root.

        For type="text" files, content can be provided via:
          - text: Inline text content
          - path: Path to file (content read at eval time)

        These are mutually exclusive - use one or the other.

        For type="json" files, provide a Nix attrset via jsonValue. Multiple
        modules can contribute to the same file path and their values will be
        deep-merged by the Nix module system.

        Example:
          # Inline text
          stackpanel.files.entries.".github/workflows/ci.yml" = {
            type = "text";
            text = "name: CI\n...";
          };

          # Path to file
          stackpanel.files.entries.".github/workflows/deploy.yml" = {
            type = "text";
            path = ./.stackpanel/src/files/.github/workflows/deploy.yml;
            description = "Deployment workflow";
          };

          # Derivation
          stackpanel.files.entries."scripts/deploy.sh" = {
            type = "derivation";
            drv = pkgs.writeScript "deploy" "#!/bin/bash\n...";
            mode = "0755";
          };

          # JSON (deep-mergeable from multiple modules)
          stackpanel.files.entries."apps/web/package.json" = {
            type = "json";
            jsonValue = {
              name = "web";
              private = true;
              scripts.dev = "vite dev";
              dependencies.react = "^19.0.0";
            };
          };
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
                  "json"
                ];
                default = "text";
                description = ''
                  Type of file content:
                  - 'text': inline text content
                  - 'derivation': copy from a derivation
                  - 'symlink': create a symbolic link
                  - 'json': Nix value serialized to formatted JSON (supports deep merge from multiple modules)
                '';
              };

              text = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Text content for the file (when type = 'text').
                  Mutually exclusive with `path` - use one or the other.
                '';
              };

              jsonValue = lib.mkOption {
                type = types.attrsOf types.anything;
                default = { };
                description = ''
                  Nix attrset to serialize as formatted JSON (when type = 'json').

                  Multiple modules can contribute to the same file path and their
                  values will be deep-merged by the Nix module system. This is
                  ideal for shared files like package.json where different modules
                  need to add scripts, dependencies, etc.

                  Example:
                    # Module A
                    stackpanel.files.entries."package.json" = {
                      type = "json";
                      jsonValue = {
                        name = "my-app";
                        scripts.dev = "bun run dev";
                      };
                    };

                    # Module B (merges with A)
                    stackpanel.files.entries."package.json" = {
                      type = "json";
                      jsonValue = {
                        scripts.test = "bun test";
                        dependencies.zod = "^3.0.0";
                      };
                    };

                    # Result: { name = "my-app"; scripts = { dev = "bun run dev"; test = "bun test"; }; dependencies = { zod = "^3.0.0"; }; }
                '';
              };

              path = lib.mkOption {
                type = types.nullOr types.path;
                default = null;
                description = ''
                  Path to file content (when type = 'text').
                  Content is read from this file at eval time.
                  Mutually exclusive with `text` - use one or the other.
                '';
                example = lib.literalExpression "./.stackpanel/src/files/.github/workflows/ci.yml";
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
