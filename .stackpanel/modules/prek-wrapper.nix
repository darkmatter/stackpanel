# ==============================================================================
# prek-wrapper.nix
#
# Adds a wrapped `prek` command that:
# - Generates .pre-commit-config.yaml on demand if missing
# - Ensures a no-op hook is present so `prek` never errors on empty configs
# ==============================================================================
{ config, lib, ... }@args:
let
  cfg =
    if config ? stackpanel then config.stackpanel else { enable = false; };
  pkgs = args.pkgs or null;
  prekPkg = if pkgs != null && pkgs ? prek then pkgs.prek else null;

  noopHook = ''
repos:
  - repo: local
    hooks:
      - id: stackpanel-noop
        name: Stackpanel noop hook
        entry: bash -c 'echo "No pre-commit hooks configured yet (noop)."'
        language: system
        pass_filenames: false
'';
in
{
  config = lib.mkIf ((cfg.enable or false) && pkgs != null) {
    stackpanel.scripts."stackpanel:prek" = {
      description = "Run prek with on-demand .pre-commit-config.yaml (with noop hook)";
      runtimeInputs = lib.optional (prekPkg != null) prekPkg;
      exec = ''
        set -euo pipefail

        ROOT="''${STACKPANEL_ROOT:-$(pwd)}"
        CONFIG_FILE="$ROOT/.pre-commit-config.yaml"

        ensure_config() {
          if [[ ! -f "$CONFIG_FILE" ]]; then
            printf '%s\n' "${noopHook}" >"$CONFIG_FILE"
            echo "🧰 Generated $CONFIG_FILE with a noop hook"
            return
          fi

          if ! grep -q "stackpanel-noop" "$CONFIG_FILE"; then
            if ! grep -q "^repos:" "$CONFIG_FILE"; then
              echo "" >>"$CONFIG_FILE"
              echo "repos:" >>"$CONFIG_FILE"
            fi
            cat >>"$CONFIG_FILE" <<'YAML'
  - repo: local
    hooks:
      - id: stackpanel-noop
        name: Stackpanel noop hook
        entry: bash -c 'echo "No pre-commit hooks configured yet (noop)."'
        language: system
        pass_filenames: false
YAML
            echo "🧰 Added noop hook to $CONFIG_FILE"
          fi
        }

        ensure_config
        exec prek "$@"
      '';
    };
  };
}
