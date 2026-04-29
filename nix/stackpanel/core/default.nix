# ==============================================================================
# default.nix
#
# Main entry point for the Stackpanel core module.
#
# Imports core-only options and implementation, then sets up the foundational
# development environment: root marker, directories, env vars, shell hooks.
#
# Feature-specific options live in their own directories (apps/, services/,
# network/, secrets/, ide/, tui/, variables/).
# ==============================================================================
{
  config,
  lib,
  pkgs ? null,
  ...
}:
let
  # pkgs is optional - provided by devenv/flakeModule via _module.args
  # or passed directly in specialArgs
  cfg = config.stackpanel;
  pathsLib = import ../lib/paths.nix { inherit lib; };
in
{
  imports = [
    ./options
    ./aliases.nix
    ./cli.nix
    ./extensions.nix
    ./options-schema.nix

    ./state.nix
    ./tasks.nix
    ./users-options.nix
    ./util.nix
  ];

  config = lib.mkIf cfg.enable {
    # Provide marker + optional root override as data
    stackpanel.devshell.env.STACKPANEL_ROOT_MARKER = cfg.root-marker;
    stackpanel.devshell.env.STACKPANEL_ROOT_DIR_NAME = cfg.dirs.home;

    # STACKPANEL_ROOT is resolved at runtime by stackpanel_resolve_paths
    # (marker walking / git root / flake.nix detection). Not baked into the
    # derivation so the shell hash stays stable across machines.

    # Core gitignore entries — use reserved stackpanel.gitignore options.
    #
    # Uses managed = "block" so that user-written gitignore content is
    # preserved. Stackpanel only owns the marker-delimited block within
    # the file; everything outside it is untouched. On module uninstall,
    # only the managed block is removed (the file itself is kept).
    #
    # Backward compatibility:
    # - defaults.projectMarker is the new flag
    # - defaults.addProjectMarker is deprecated alias
    stackpanel.files.entries.".gitignore" = lib.mkIf cfg.gitignore.enable {
      type = "line-set";
      managed = "block";
      dedupe = true;
      sort = true;
      lines =
        (lib.optionals cfg.gitignore.defaults.stackpanelState [
          "${cfg.dirs.home}/gen/"
          "${cfg.dirs.home}/keys/"
          "${cfg.dirs.home}/profile/"
          "${cfg.dirs.home}/state/"
        ])
        ++ (lib.optionals cfg.gitignore.defaults.localConfig [
          "${cfg.dirs.home}/config.local.nix"
        ])
        ++ (lib.optionals cfg.gitignore.defaults.tasksDir [
          ".tasks"
        ])
        ++ (lib.optional (
          cfg.gitignore.defaults.projectMarker || cfg.gitignore.defaults.addProjectMarker
        ) cfg.root-marker)
        ++ cfg.gitignore.entries;
    };

    # Core hook: define funcs, resolve paths, ensure dirs + marker + gitignore
    stackpanel.devshell.hooks.before = lib.mkBefore (
      # Clean conflicting aliases (runs first, before strict mode)
      lib.optional (cfg.devshell.clean.aliases != [ ]) ''
        # Unset conflicting aliases
        ${lib.concatMapStringsSep "\n" (
          alias: "unalias ${alias} 2>/dev/null || true"
        ) cfg.devshell.clean.aliases}
      ''
      ++ [
        ''
          # syntax: bash
          set -euo pipefail

          ${pathsLib.mkShellPathUtils {
            rootDir = cfg.dirs.home;
            stateDir = "profile";
            keysDir = "keys";
            genDir = "gen";
          }}

          # If stackpanel.root was provided, prefer it; otherwise resolve via marker walking
          if [[ -n "''${STACKPANEL_ROOT:-}" ]]; then
            stackpanel_resolve_paths "$STACKPANEL_ROOT"
          else
            stackpanel_resolve_paths
          fi

          mkdir -p "$STACKPANEL_STATE_DIR" "$STACKPANEL_KEYS_DIR" "$STACKPANEL_GEN_DIR"

          # Shell logging disabled by default (requires bash for process substitution)
          # Set STACKPANEL_SHELL_LOG before entering shell to enable
          # if [[ -z "''${STACKPANEL_SHELL_LOG:-}" ]]; then
          #   export STACKPANEL_SHELL_LOG="$STACKPANEL_STATE_DIR/shell.log"
          # fi

          # Compute shell freshness hash from config files
          # This is used to detect when the shell is stale (config changed but shell not reloaded)
          _sp_compute_shell_hash() {
            local files=(
              "$STACKPANEL_ROOT/flake.nix"
              "$STACKPANEL_ROOT/flake.lock"
              "$STACKPANEL_ROOT/${cfg.dirs.home}/config.nix"
              "$STACKPANEL_ROOT/devenv.nix"
              "$STACKPANEL_ROOT/devenv.yaml"
            )
            local hash_input=""
            for f in "''${files[@]}"; do
              if [[ -f "$f" ]]; then
                hash_input+="$(cat "$f" 2>/dev/null)"
              fi
            done
            echo -n "$hash_input" | md5sum | cut -d' ' -f1
          }
          export STACKPANEL_SHELL_HASH="$(_sp_compute_shell_hash)"
          export STACKPANEL_SHELL_HASH_TIME="$(date +%s)"

          # Restore default interactive shell behavior (disable strict error handling)
          set +euo pipefail
        ''
      ]
    );

    stackpanel.devshell.hooks.after = lib.mkAfter [
      ''
        echo "stackpanel core initialized"
        # Display MOTD if enabled
        if command -v stackpanel &> /dev/null; then
          stackpanel motd
        fi

        # Log completion
        if [[ -z "''${DIRENV_IN_ENVRC:-}" ]]; then
          echo ""
          echo "═══════════════════════════════════════════════════════════════"
          echo "Shell hook completed at $(date '+%Y-%m-%d %H:%M:%S')"
          echo "Log saved to: ''${STACKPANEL_STATE_DIR:-$PWD/.stack/profile}/shell.log"
          echo "═══════════════════════════════════════════════════════════════"
        fi
      ''
    ];

    # local overrides
  };
}
