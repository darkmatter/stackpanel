# ==============================================================================
# setup-tasks.nix
#
# Track and display incomplete setup tasks in the development shell.
#
# This module provides a simple framework for checking setup prerequisites and
# displaying actionable messages to users when they enter the shell.
#
# Currently supports checking for age encryption keys.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.devshell.setup-tasks;

  # Simple checker script for age keys
  ageKeyChecker = pkgs.writeShellScriptBin "check-age-keys" ''
    set +e

    KEYS_DIR=".keys"

    if [[ -d "$KEYS_DIR" ]] && [[ -n "$(find "$KEYS_DIR" -type f -name "*.age" 2>/dev/null)" ]]; then
      exit 0  # Keys found
    else
      exit 1  # Keys missing
    fi
  '';

  # Main setup checker that runs all checks
  setupChecker = pkgs.writeShellScriptBin "check-setup-tasks" ''
    set +e

    INCOMPLETE_TASKS=()

    # Check age keys if enabled
    if ${lib.boolToString cfg.checkAgeKeys}; then
      if ! ${ageKeyChecker}/bin/check-age-keys; then
        INCOMPLETE_TASKS+=("age-keys")
      fi
    fi

    # Display results
    if [[ ''${#INCOMPLETE_TASKS[@]} -eq 0 ]]; then
      ${lib.optionalString (!cfg.silent) ''
        echo "✓ All setup tasks complete"
      ''}
      exit 0
    fi

    ${lib.optionalString (!cfg.silent) ''
      echo ""
      echo "⚠ Setup tasks incomplete:"
      echo ""

      for task in "''${INCOMPLETE_TASKS[@]}"; do
        case "$task" in
          age-keys)
            echo "  ✗ Age encryption keys"
            echo "    Required for encrypting/decrypting secrets with SOPS"
            echo "    → Run 'age:fetch' to download keys from vals"
            echo ""
            ;;
        esac
      done
    ''}

    exit 0
  '';

in
{
  options.stackpanel.devshell.setup-tasks = {
    enable = lib.mkEnableOption "setup tasks tracking and display" // {
      default = true;
      description = ''
        Enable shell-entry checks for setup prerequisites.

        When enabled, Stackpanel installs the setup checker in the devshell and
        runs it from hooks.after. Checks are informational and must not fail shell
        entry; they print actionable commands for missing local setup.
      '';
      example = true;
    };

    silent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Suppress setup-task status output during shell entry.

        The checker still runs and returns success, but it does not print the
        "all complete" or "incomplete" messages. Use this for CI or quiet direnv
        reloads where setup state is checked elsewhere.
      '';
      example = true;
    };

    checkAgeKeys = lib.mkOption {
      type = lib.types.bool;
      default = config.stackpanel.secrets.age-key-cmd.enable or false;
      description = ''
        Check whether local age encryption keys are available for SOPS secrets.

        Defaults to the age-key command feature state. When true, shell entry
        reports missing `.age` keys and points the user at `age:fetch` instead of
        failing later during secret decryption.
      '';
      example = true;
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages = [
      setupChecker
      ageKeyChecker
    ];

    stackpanel.devshell.hooks.after = lib.mkAfter [
      "${setupChecker}/bin/check-setup-tasks || true"
    ];
  };
}
