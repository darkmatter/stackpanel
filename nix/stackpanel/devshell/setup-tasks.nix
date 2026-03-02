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
    };

    silent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't display task check results on shell entry";
    };

    checkAgeKeys = lib.mkOption {
      type = lib.types.bool;
      default = config.stackpanel.secrets.age-key-cmd.enable or false;
      description = "Check if age encryption keys are available";
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
