# ==============================================================================
# devenv.nix
#
# Devenv configuration for standalone usage (with devenv.yaml).
# Run `devenv shell` to enter the dev environment.
#
# Documentation: https://devenv.sh/reference/options/
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
{
  # ---------------------------------------------------------------------------
  # Stackpanel Configuration (edit ./.stackpanel/config.nix)
  # _internal.nix handles merging with data tables and GitHub collaborators
  # ---------------------------------------------------------------------------
  stackpanel = import ./.stackpanel/_internal.nix { inherit pkgs lib; };

  # ---------------------------------------------------------------------------
  # Packages - Available in the dev shell
  # ---------------------------------------------------------------------------
  packages = with pkgs; [
    git
    jq
    # Add your packages here
  ];

  # ---------------------------------------------------------------------------
  # Languages - Enable language toolchains
  # ---------------------------------------------------------------------------
  languages = {
    # javascript = {
    #   enable = true;
    #   bun.enable = true;
    #   bun.install.enable = true;
    # };

    # typescript.enable = true;

    # go.enable = true;

    # python = {
    #   enable = true;
    #   version = "3.12";
    # };
  };

  # ---------------------------------------------------------------------------
  # Environment Variables
  # ---------------------------------------------------------------------------
  env = {
    # DATABASE_URL = "postgres://localhost:5432/myapp";
    # NODE_ENV = "development";
  };

  # ---------------------------------------------------------------------------
  # Shell Hook - Runs when entering the shell
  # ---------------------------------------------------------------------------
  enterShell = ''
    echo "Welcome to the dev environment!"
  '';

  # ---------------------------------------------------------------------------
  # Processes - Run with `devenv up`
  # ---------------------------------------------------------------------------
  # processes = {
  #   server.exec = "bun run dev";
  #   worker.exec = "bun run worker";
  # };

  # ---------------------------------------------------------------------------
  # Services - Managed services
  # ---------------------------------------------------------------------------
  # services.postgres = {
  #   enable = true;
  #   initialDatabases = [{ name = "myapp"; }];
  # };

  # services.redis.enable = true;
}
