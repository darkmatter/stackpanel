# ==============================================================================
# cli.nix
#
# CLI configuration options - control stackpanel CLI behavior.
#
# The Stackpanel CLI (written in Go) handles file generation and other
# imperative operations that are triggered from the Nix devenv.
#
# Options:
#   - enable: Enable CLI-based file generation (default: true)
#   - quiet: Suppress generation output messages
#
# When enabled, the CLI is invoked during enterShell to generate:
#   - State files (.stack/state/stackpanel.json)
#   - IDE configurations (.stack/gen/ide/)
#   - JSON schemas (.stack/gen/schemas/)
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.cli = {
    enable = lib.mkEnableOption "CLI-based file generation" // {
      default = false;
    };

    quiet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Suppress generation output messages";
    };
  };
}
