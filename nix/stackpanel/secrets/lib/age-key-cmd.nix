# ==============================================================================
# age-key-cmd.nix
#
# NixOS/home-manager module for age key management with SOPS.
#
# Provides a module interface to configure the age-key-tools derivations.
# This allows declarative configuration of age key sources (like 1Password)
# and automatic setup of SOPS_AGE_KEY_CMD in development shells.
#
# Usage:
#   stackpanel.secrets.age-key-cmd = {
#     enable = true;
#     keysDir = ".keys";
#     onePassword = {
#       account = "voytravel";
#       item = "op://voy-508-shared/sops-dev";
#     };
#   };
# ==============================================================================
{ config, lib, pkgs, ... }:

let
  cfg = config.stackpanel.secrets.age-key-cmd;

  # Build age key tools with module configuration
  ageKeyTools = pkgs.callPackage ./age-key-tools.nix {
    keysDir = cfg.keysDir;
    valsRef = cfg.valsRef;
  };

in
{
  options.stackpanel.secrets.age-key-cmd = {
    enable = lib.mkEnableOption "age key management tools for SOPS";

    keysDir = lib.mkOption {
      type = lib.types.str;
      default = ".keys";
      description = ''
        Directory to store cached age keys.
        Should be added to .gitignore as it contains sensitive private keys.
      '';
    };

    valsRef = lib.mkOption {
        type = lib.types.str;
        description = "Vals reference (ref+awsssm://...) to an AGE private key.";
    };

    autoSetup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically configure SOPS_AGE_KEY_CMD in the development shell.
        If false, you'll need to manually export SOPS_AGE_KEY_CMD.
      '';
    };

    addToDevShell = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add age key tools to devShell packages";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add tools to devShell
    stackpanel.devshell.packages = lib.mkIf cfg.addToDevShell [
      ageKeyTools.fetchAgeKey
      ageKeyTools.ageKeyCmd
      ageKeyTools.checkAgeKeys
      ageKeyTools.sopsWithAgeKey
    ];

    # Auto-configure SOPS_AGE_KEY_CMD
    stackpanel.devshell.env = lib.mkIf cfg.autoSetup {
      SOPS_AGE_KEY_CMD = "${ageKeyTools.ageKeyCmd}/bin/age-key-cmd";
      SOPS_KEYS_DIR = cfg.keysDir;
      VALS_REF_AGE_PRIV = cfg.valsRef;
    };

    # Add helper scripts
    stackpanel.scripts = {
      "age:fetch" = {
        exec = "${ageKeyTools.fetchAgeKey}/bin/fetch-age-key";
        description = "Fetch age keys from vals and cache locally";
      };

      "age:check" = {
        exec = "${ageKeyTools.checkAgeKeys}/bin/check-age-keys";
        description = "Check if age keys are available and list them";
      };
    };

    # Ensure keys directory is in .gitignore
    stackpanel.files.entries.".gitignore".lines = [
      "# Age keys (secrets) - managed by stackpanel.secrets.age-key-cmd"
      "/${cfg.keysDir}/"
    ];
  };
}
