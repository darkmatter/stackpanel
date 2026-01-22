# ==============================================================================
# state.nix
#
# State options for Stackpanel - holds runtime/derived state for serialization.
#
# This module defines options for data that modules can contribute to the
# state.json file. The state is serialized and made available to the CLI/agent
# for use without re-evaluating Nix.
#
# Structure:
#   stackpanel.state.file - state file name
#   stackpanel.state.devenv - devenv schema/state (services, languages, hooks)
#   stackpanel.state.custom - arbitrary module-contributed state
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.state = {
    file = lib.mkOption {
      type = lib.types.str;
      default = "stackpanel.json";
      description = "Name of the state file written to the state directory.";
    };

    # Devenv integration state (populated by devenv-*.nix modules)
    devenv = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Devenv-related state for serialization.
        Populated by devenv integration modules (services, languages, pre-commit).

        Structure:
          {
            services = { available = [...]; enabled = [...]; };
            languages = { available = [...]; enabled = [...]; };
            preCommit = { available = [...]; enabled = [...]; };
          }
      '';
    };

    # Arbitrary module-contributed state
    custom = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Arbitrary state data contributed by modules.
        Use this for module-specific state that should be serialized.
      '';
    };
  };
}
