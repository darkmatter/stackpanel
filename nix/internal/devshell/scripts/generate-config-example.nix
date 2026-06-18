# ==============================================================================
# generate-config-example.nix  (INTERNAL — stackpanel development only)
#
# Convenience wrapper inside the stackpanel repo's devshell.
#
# It simply cats one of the two checked-in starter configs
# (nix/flake/templates/{default,minimal}/.stack/config.nix) into the tree as
# config.nix.example.
#
# This is only for people working on stackpanel itself. End users use the
# shipped binary:
#
#   stack config generate [--no-comments] [--output PATH]
#
# Which does the equivalent of "emit the baked starter".
#
# Placed under nix/internal so it is not mistaken for user-facing stackpanel
# configuration.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;

  defaultSrc = ../../../flake/templates/default/.stack/config.nix;
  minimalSrc = ../../../flake/templates/minimal/.stack/config.nix;

  generateConfigExampleScript = pkgs.writeShellScriptBin "stackpanel-generate-config-example" ''
    set -euo pipefail

    OUTPUT_PATH="''${STACKPANEL_ROOT:-$(pwd)}/.stack/config.nix.example"
    USE_MINIMAL=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-comments)
          USE_MINIMAL=true
          shift
          ;;
        --output|-o)
          OUTPUT_PATH="$2"
          shift 2
          ;;
        --help|-h)
          echo "Usage: generate-config-example [--no-comments] [--output PATH]"
          echo ""
          echo "Copy a checked-in starter config.nix.example (stackpanel repo only)."
          echo ""
          echo "  --no-comments     Minimal template"
          echo "  --output, -o PATH Destination (default: .stack/config.nix.example)"
          exit 0
          ;;
        *)
          echo "Unknown option: $1"
          exit 1
          ;;
      esac
    done

    mkdir -p "$(dirname "$OUTPUT_PATH")"
    if [ "$USE_MINIMAL" = true ]; then
      cat ${minimalSrc} > "$OUTPUT_PATH"
    else
      cat ${defaultSrc} > "$OUTPUT_PATH"
    fi
    echo "Generated: $OUTPUT_PATH"
  '';
in
{
  config.stackpanel.scripts.generate-config-example = lib.mkIf cfg.enable {
    description = "INTERNAL: Copy starter config.nix.example from checked-in templates";
    exec = ''
      ${generateConfigExampleScript}/bin/stackpanel-generate-config-example "$@"
    '';
  };
}
