# stackpanel development environment
#
# This file configures the devenv shell for local development.
#
{
  pkgs,
  lib,
  config,
  ...
}: let
  # Optimization to reduce size of cachix by ~4 GB!
  cachixBin = pkgs.cachix.bin;
  cachixSlim = {
    type = "derivation";
    name = cachixBin.name;
    outPath = cachixBin.outPath;
    outputs = ["out"];
    out = cachixSlim;
    outputName = "out";
  };
  formatters = [
    "biome"
    "alejandra"
    "mdformat"
  ];
in {
  # Enable stackpanel modules
  stackpanel = {
    enable = true;

    # Theme with starship prompt
    theme.enable = true;

    # Uncomment and configure as needed:
    #
    # AWS cert-based authentication
    # aws.certAuth = {
    #   enable = true;
    #   accountId = "YOUR_ACCOUNT_ID";
    #   roleName = "YOUR_ROLE_NAME";
    #   trustAnchorArn = "arn:aws:rolesanywhere:...";
    #   profileArn = "arn:aws:rolesanywhere:...";
    # };
    #
    # Step CA certificate management
    network.step = {
      enable = true;
      caUrl = "https://ca.internal:443";
      caFingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
    };
  };

  # Core packages
  packages = with pkgs; [
    # Node.js ecosystem
    bun
    nodejs_22

    # Go (for agent)
    go

    # Dev tools
    jq
    git
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
    # Add any project-specific env vars here
  };

  # Shell hooks
  enterShell = ''
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  stackpanel Development Environment                           ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📦 Available Commands:"
    echo "  bun install          # Install dependencies"
    echo "  bun run dev          # Start development server"
    echo "  cd agent && make     # Build the agent"
    echo ""
  '';

  # Formaattingdevev
  git-hooks.enable = true;
  git-hooks.install.enable = true;
  git-hooks.hooks.commitizen.enable = true;
  git-hooks.hooks.treefmt.enable = true;
  git-hooks.default_stages = [
    "pre-commit"
    "pre-push"
    "commit-msg"
  ];
  git-hooks.hooks.treefmt.settings.formatters = [
    pkgs.alejandra
    pkgs.biome
    pkgs.mdformat
  ];
  treefmt.enable = true;
  treefmt.config.programs.alejandra.enable = true;
  treefmt.config.programs.biome.enable = true;
  treefmt.config.programs.mdformat.enable = true;
}
