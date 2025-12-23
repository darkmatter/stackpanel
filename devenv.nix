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
in {
  imports = [
    ./infra/devenv/devenv.nix
  ];
  # Enable stackpanel modules
  stackpanel = {
    enable = true;

    # Theme with starship prompt
    theme.enable = true;

    # IDE integration
    ide.enable = true;
    ide.vscode.enable = true;

    devenv.recommended.enable = true;
    devenv.recommended.formatters.enable = true;
    # Uncomment and configure as needed:
    #
    # AWS cert-based authentication
    aws.certAuth = {
      enable = true;
      region = "us-west-2";
      account-id = "950224716579";
      role-name = "darkmatter-dev";
      trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:trust-anchor/c99a9383-6be1-48ba-8e63-c3ab6b7069cb";
      profile-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:profile/4e72b392-9074-4e53-8cd0-1ba50856d1ca";
    };
    #
    # Step CA certificate management
    network.step = {
      enable = true;
      ca-url = "https://ca.internal:443";
      ca-fingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
    };
  };
  # devenv.debug = true;

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

  # processes = {
  #   # Start stackpanel agent in dev mode
  #   # server = {
  #   #   cwd = "${config.git.root}/apps/server";
  #   #   exec = "${pkgs.bun}/bin/bun run dev";
  #   # };
  #   # web = {
  #   #   cwd = "${config.git.root}/apps/web";
  #   #   exec = "${pkgs.bun}/bin/bun dev";
  #   # };
  #   fullstack = {
  #     cwd = "${config.git.root}";
  #     exec = "${pkgs.bun}/bin/bun x alchemy dev";
  #   };
  #   stackpanel-agent = {
  #     cwd = "${config.git.root}/apps/agent";
  #     exec = "${pkgs.go}/bin/go run ./cmd/agent --dev";
  #   };
  #   docs = {
  #     cwd = "${config.git.root}/docs";
  #     exec = "${pkgs.bun}/bin/bun dev";
  #   };
  # };

  # Environment variables
  env = {
    # Add any project-specific env vars here
    EDITOR = "vim";
    # Step CA config for stackpanel CLI
    STEP_CA_URL = "https://ca.internal:443";
    STEP_CA_FINGERPRINT = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
  };

  # Shell hooks
  enterShell = ''
    # syntax: bash
    # Build stackpanel CLI if needed
    if [[ ! -f "$DEVENV_STATE/stackpanel" ]] || [[ "$DEVENV_ROOT/cli/main.go" -nt "$DEVENV_STATE/stackpanel" ]]; then
      echo "Building stackpanel CLI..."
      (cd "$DEVENV_ROOT/cli" && go build -o "$DEVENV_STATE/stackpanel" . 2>/dev/null) || true
    fi
    export PATH="$DEVENV_STATE:$PATH"

    # Authenticate AWS certs on shell entry
    eval "$(aws-creds-env)" || true
  '';

  # Add project-specific commands to MOTD
  stackpanel.motd.commands = [
    {
      name = "stackpanel status";
      description = "Show all service status";
    }
    {
      name = "stackpanel services start";
      description = "Start dev services";
    }
    {
      name = "stackpanel caddy add";
      description = "Add a Caddy site";
    }
    {
      name = "stackpanel certs ensure";
      description = "Get device certificate";
    }
    {
      name = "bun install";
      description = "Install dependencies";
    }
    {
      name = "bun run dev";
      description = "Start development server";
    }
  ];
  stackpanel.motd.hints = [
    "Run 'stackpanel --help' for all commands"
    "Run 'devenv up' to start all processes"
  ];

  # Formaattingdevev
  # git-hooks.enable = true;
  # git-hooks.install.enable = true;
  # git-hooks.hooks.commitizen.enable = true;
  # git-hooks.hooks.treefmt.enable = true;
  # git-hooks.default_stages = [
  #   "pre-commit"
  #   "pre-push"
  #   "commit-msg"
  # ];
  # treefmt.enable = true;
  # treefmt.config.programs.alejandra.enable = true;
  # treefmt.config.programs.mdformat.enable = true;
  # treefmt.config.programs.mdformat.settings.number = true;
  # treefmt.config.programs.biome.enable = true;
  # treefmt.config.programs.biome.command = "${config.git.root}/node_modules/.bin/biome";
}
