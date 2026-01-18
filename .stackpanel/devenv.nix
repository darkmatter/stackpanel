# ==============================================================================
# .stackpanel/devenv.nix
#
# Devenv-specific configuration for the stackpanel project.
#
# This file is evaluated by:
#   1. `nix develop` - flakeModule extracts packages, env, enterShell, languages
#   2. `devenv shell` - full devenv evaluation with services, processes, etc.
#
# Stackpanel config belongs in config.nix, not here.
# ==============================================================================
{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  # ===========================================================================
  # Packages
  # ===========================================================================
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

  # ===========================================================================
  # Languages (devenv adds packages and sets up tooling automatically)
  # ===========================================================================
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

  # ===========================================================================
  # Environment Variables
  # ===========================================================================
  env = {
    STACKPANEL_SHELL_ID = "1";
    EDITOR = "vim";
    STEP_CA_URL = "https://ca.internal:443";
    STEP_CA_FINGERPRINT = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
  };

  # ===========================================================================
  # Shell Hook
  # ===========================================================================
  enterShell = ''
    echo "✅ Devenv for the stackpanel repository"
  '';

  # ===========================================================================
  # Pre-commit Hooks (devenv-native format)
  # ===========================================================================
  pre-commit.hooks = {
    nixfmt-rfc-style.enable = true;
    gofmt.enable = true;
  };
}
