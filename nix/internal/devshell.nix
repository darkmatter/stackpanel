# ==============================================================================
# devshell.nix
#
# Local development shell configuration for the stackpanel repository itself.
# This is the "dogfooding" config - we use our own modules to develop stackpanel.
#
# Usage in flake.nix:
#   devenv.shells.default.imports = [ (import ./nix/internal/devshell.nix) ];
# ==============================================================================
{ pkgs, lib, ... }:
{
  # Import stackpanel modules
  imports = [
    # Main stackpanel module (all features available via options)
    ../flake/modules/devenv.nix
    # Internal devenv config (services, modules we're developing)
    ./devenv/devenv.nix
  ];

  # Stackpanel options (imported from separate file for cleaner organization)
  stackpanel = import ./stackpanel.nix;

  # ===========================================================================
  # Devenv options below (packages, languages, env, enterShell, etc.)
  # ===========================================================================

  # Core packages for development
  packages = with pkgs; [
    bun
    nodejs_22
    go
    air # Go live reload for CLI development
    jq
    git
    nixd
    nixfmt
  ];

  # Languages
  languages = {
    javascript = {
      enable = true;
      bun.enable = true;
      bun.install.enable = true;
    };
    typescript.enable = true;
    go = {
      enable = true;
      package = pkgs.go;
    };
  };

  # Environment variables
  env = {
    STACKPANEL_SHELL_ID = "1";
    EDITOR = "vim";
    STEP_CA_URL = "https://ca.internal:443";
    STEP_CA_FINGERPRINT = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
  };

  enterShell = ''
    echo "✅ Devenv for the stackpanel repository"
  '';
}
