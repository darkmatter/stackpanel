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
  inherit (lib) types;
  db = import ../db { inherit lib; };
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
      description = ''
        Packages installed into the generated devshell.

        Feature modules append concrete package values here after resolving any
        top-level stackpanel.packages strings. These packages feed PATH, the
        unified devshell profile, and .stack/bin generation.
      '';
      example = lib.literalExpression ''
        [ pkgs.git pkgs.ripgrep pkgs.nodejs_22 ]
      '';
    };
    nativeBuildInputs = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Native build tools needed by shell users or local package builds.

        Prefer stackpanel.devshell.packages for normal CLI tools. Use this when
        downstream Nix shell adapters need conventional mkShell nativeBuildInputs,
        such as pkg-config or cmake.
      '';
      example = lib.literalExpression ''
        [ pkgs.pkg-config pkgs.cmake ]
      '';
    };
    buildInputs = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Runtime/build libraries exposed to native compilation in the devshell.

        Use for headers and linker inputs needed by local language package
        managers, such as OpenSSL or zlib. Command-line tools belong in
        stackpanel.devshell.packages.
      '';
      example = lib.literalExpression ''
        [ pkgs.openssl pkgs.zlib ]
      '';
    };

    env = lib.mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Environment variables exported before feature hooks run.

        Values are shell-escaped and rendered as `export NAME=value` in the
        before hook. Use for stable non-secret config such as app modes, local
        URLs, or tool flags. Secrets should come from the secrets modules.
      '';
      example = {
        NODE_ENV = "development";
        RUST_LOG = "info";
        STACKPANEL_APP = "web";
      };
    };

    path.prepend = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        PATH entries inserted before inherited PATH during shell startup.

        Use for repo-local wrappers that must take priority over package
        binaries, such as .stack/bin or generated scripts. Entries are strings
        because they may reference runtime env vars like $STACKPANEL_ROOT.
      '';
      example = [
        "$STACKPANEL_ROOT/.stack/bin"
        "$STACKPANEL_ROOT/node_modules/.bin"
      ];
    };
    path.append = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        PATH entries appended after inherited PATH during shell startup.

        Use for fallback tools that should not shadow Nix-provided packages.
        Prefer path.prepend only when a repo-local wrapper intentionally wins.
      '';
      example = [ "$STACKPANEL_ROOT/scripts/bin" ];
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
      description = ''
        Start the devshell from a minimal parent environment.

        When enabled, Stackpanel preserves only variables listed in
        stackpanel.devshell.clean.keep and related keep* sets. Use to catch
        hidden host-machine dependencies and make shell entry more reproducible.
      '';
      example = true;
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
      example = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
        "DBUS_SESSION_BUS_ADDRESS"
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
        "XDG_CACHE_HOME"
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
      description = ''
        Shell snippets that run before main devshell hooks.

        Stackpanel renders env exports and PATH edits here with mkBefore so later
        feature hooks see a prepared environment. Use for cheap setup that must
        happen before services, scripts, or prompts are announced.
      '';
      example = [
        ''export BUN_INSTALL="$STACKPANEL_ROOT/.bun"''
        ''mkdir -p "$STACKPANEL_ROOT/.stack/state"''
      ];
    };
    hooks.main = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Primary shell-entry hook snippets for feature status and setup.

        Feature modules append here for user-visible shell entry behavior, such
        as announcing loaded scripts or starting lightweight checks. Keep snippets
        idempotent because direnv may rerun them often.
      '';
      example = [ ''echo "stackpanel scripts loaded"'' ];
    };
    hooks.after = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Shell snippets that run after main devshell hooks.

        Use for cleanup, generated symlinks, GC roots, and checks that should see
        final PATH and env. Examples include .stack/bin generation, setup-task
        checks, and profile symlink refreshes.
      '';
      example = [
        "stackpanel-generate-bin || true"
        "check-setup-tasks || true"
      ];
    };
    timing = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        If true, every hook will log timing information to the console. Useful for
        debugging hook performance.
      '';
      example = true;
    };

    # Internal: Serializable script definitions for CLI/TUI access
    _commandsSerializable = lib.mkOption {
      description = ''
        Internal serializable script definitions for CLI, TUI, and agent access.

        Generated from stackpanel.scripts. Values intentionally contain command
        metadata and derivation-backed exec paths rather than inline script
        bodies, so external callers can run pinned commands safely.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            name = lib.mkOption {
              type = types.str;
              description = ''
                Command name exposed to CLI/TUI surfaces.

                Mirrors the stackpanel.scripts attribute key and should remain
                stable because UI command lists may reference it directly.
              '';
              example = "db-seed";
            };
            exec = lib.mkOption {
              type = types.str;
              description = ''
                Executable path used by the CLI/agent to run this command.

                Generated from the per-script derivation path rather than inline
                shell text, so callers execute a pinned store path without sh -c.
              '';
              example = "/nix/store/abc123-stackpanel-scripts/bin/db-seed";
            };
            description = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Optional help text shown beside this command in command surfaces.

                Keep short and action-oriented because it appears in command
                pickers, MOTD output, and Studio command lists.
              '';
              example = "Seed local database with fixture data";
            };
            env = lib.mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = ''
                Environment values attached to command metadata.

                Copied from stackpanel.scripts.<name>.env. Do not place plaintext
                secrets here; reference generated secret env instead.
              '';
              example = {
                NODE_ENV = "development";
                DATABASE_URL = "$STACKPANEL_DATABASE_URL";
              };
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
      description = ''
        Enable Stackpanel-managed generated files.

        Entries under stackpanel.files.entries are written by the Go generator.
        Use for editor config, generated JSON manifests, wrapper scripts, and
        symlinks declared by Nix modules.
      '';
      example = true;
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
            path = ./.stack/src/files/.github/workflows/deploy.yml;
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
        types.submodule (_: {
          options = {
            enable = lib.mkEnableOption "Generate this file" // {
              default = true;
              description = ''
                Enable generation for this single file entry.

                Set false to keep a contributed entry in module config while
                suppressing the actual write, useful for temporary overrides.
              '';
              example = false;
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
              example = "json";
            };

            text = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Text content for the file (when type = 'text').
                Mutually exclusive with `path` - use one or the other.
              '';
              example = ''
                #!/usr/bin/env bash
                exec stackpanel commands "$@"
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
              example = {
                name = "web";
                private = true;
                scripts = {
                  dev = "vite dev";
                  build = "vite build";
                };
              };
            };

            path = lib.mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to file content (when type = 'text').
                Content is read from this file at eval time.
                Mutually exclusive with `text` - use one or the other.
              '';
              example = lib.literalExpression "./.stack/src/files/.github/workflows/ci.yml";
            };

            drv = lib.mkOption {
              type = types.nullOr types.package;
              default = null;
              description = ''
                Derivation whose outPath contains the file content when type = "derivation".

                Use for generated executables or config assembled by Nix builders.
                The file generator copies the derivation output instead of reading
                plaintext at eval time.
              '';
              example = lib.literalExpression ''
                pkgs.writeTextFile {
                  name = "deploy.sh";
                  text = "#!/usr/bin/env bash\nexec stackpanel deploy \"$@\"\n";
                  executable = true;
                }
              '';
            };

            target = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Symlink target path when type = "symlink".

                Targets may be absolute Nix store paths or repo-relative paths.
                Use for stable refs such as .stack/bin tools or generated config
                that should point at another managed file.
              '';
              example = "/nix/store/abc123-task/bin/task";
            };

            mode = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Optional chmod mode applied after file generation.

                Use "0755" for generated scripts and wrappers, or "0644" for
                regular config files. Null leaves the generator default intact.
              '';
              example = "0755";
            };

            source = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Module or component that contributed this generated file.

                Used by UI and inventory surfaces to show ownership, making it
                clear whether a file came from IDE, direnv, scripts, or another
                Stackpanel module.
              '';
              example = "ide.nix";
            };

            description = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Human-readable description of this generated file's purpose.

                Use practical wording that helps users decide whether to inspect,
                edit the source module, or disable the entry.
              '';
              example = "VS Code workspace configuration";
            };
          };
        })
      );
      default = { };
      example = lib.literalExpression ''
        {
          ".github/workflows/ci.yml" = {
            type = "text";
            path = ./.stack/src/files/.github/workflows/ci.yml;
            description = "CI workflow generated from Stackpanel config";
          };

          "apps/web/package.json" = {
            type = "json";
            jsonValue = {
              scripts.dev = "vite dev";
              dependencies.react = "^19.0.0";
            };
          };

          "scripts/deploy" = {
            type = "derivation";
            drv = pkgs.writeShellScriptBin "deploy" "exec stackpanel deploy \"$@\"";
            mode = "0755";
          };
        }
      '';
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
