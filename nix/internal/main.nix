# ==============================================================================
# stackpanel.nix
#
# Stackpanel-specific options for the stackpanel repository itself.
# This file contains configuration for multiple systems, each under their own key:
#   - stackpanel: Stackpanel module options
#   - devenv: Devenv-specific options (packages, languages, env, etc.)
#   - git-hooks: Git hooks configuration
#
# Imported by devshell.nix which extracts each section appropriately.
# ==============================================================================
{ pkgs, lib, config, inputs, ... }:
{
  # ===========================================================================
  # Stackpanel options
  # ===========================================================================
  stackpanel = {
    github = "darkmatter/stackpanel";
    enable = true;
    debug = true;
    useDevenv = false;  # false = force native shell even with devenv config
    theme.enable = true;
    ide.enable = true;
    ide.vscode.enable = true;
    cli.enable = true;

    # Packages for the devshell
    packages = with pkgs; [
      air
      nixd
      git
      jq
      go
      prek
    ];

    # AWS Roles Anywhere via stackpanel's AWS module
    aws.roles-anywhere = {
      enable = true;
      region = "us-west-2";
      account-id = "950224716579";
      role-name = "darkmatter-dev";
      trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:trust-anchor/c99a9383-6be1-48ba-8e63-c3ab6b7069cb";
      profile-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:profile/4e72b392-9074-4e53-8cd0-1ba50856d1ca";
    };

    # Step CA
    step-ca = {
      enable = true;
      ca-url = "https://ca.internal:443";
      ca-fingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
      provisioner = "Authentik";
      prompt-on-shell = true;
      cert-name = "device";
    };

    users = {
      cooper = {
        name = "Cooper Maruyama";
        github = "coopmoney";
        public-keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINh0gA7reCRW+zQ5pPpIjoJGpaFQSbC/4K8B6vMXJVr+ cooper@darkmatter.io" ];
        secrets-allowed-environments = [ "web/dev" "web/staging" "web/production" ];
      };
    };

    secrets =  {
      input-directory = "infra/secrets";
      # enable = true;
      environments = {
        "web/dev" = {
          name = "dev";
          sources = [ "shared" "dev" ];
          public-keys = [ "age1..." ];
        };
        "web/staging" = {
          name = "staging";
          sources = [ "shared" "staging" ];
          public-keys = [ "age1..." ];
        };
        "web/production" = {
          name = "production";
          sources = [ "shared" "production" ];
          public-keys = [ "age1..." ];
        };
      };
    };

    # MOTD content
    motd.enable = true;
    motd.commands = [
      {
        name = "aws-creds-env";
        description = "Export AWS credentials to environment";
      }
    ];

    devshell.hooks.main = [
      ''
        echo "✅ Stackpanel development environment"
      ''
    ];
  };

  # ===========================================================================
  # Devenv options (packages, languages, env, enterShell, etc.)
  # ===========================================================================
  devenv = {
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

    env = {
      STACKPANEL_SHELL_ID = "1";
      EDITOR = "vim";
      STEP_CA_URL = "https://ca.internal:443";
      STEP_CA_FINGERPRINT = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
    };

    enterShell = ''
      echo "✅ Devenv for the stackpanel repository"
    '';
  };

  # ===========================================================================
  # Git hooks configuration (for git-hooks.nix / pre-commit)
  # ===========================================================================
  git-hooks = {
    enable = true;
    # Add hook configurations here, e.g.:
    # nixfmt-rfc-style.enable = true;
    # gofmt.enable = true;
    git-hooks.package = pkgs.prek;
  };
}
