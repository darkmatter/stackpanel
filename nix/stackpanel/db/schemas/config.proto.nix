# ==============================================================================
# config.proto.nix
#
# Protobuf schema for Stackpanel project configuration.
# This is the root configuration file at .stack/config.nix
#
# This file also contains boilerplate templates for scaffolding new projects.
# The `stackpanel scaffold` command and `nix flake init` templates use these.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "config.proto";
  package = "stackpanel.db";

  # ==========================================================================
  # User-editable config.nix boilerplate
  # This is the main configuration file users edit
  # ==========================================================================
  boilerplate = ''
    # ==============================================================================
    # config.nix
    #
    # Stackpanel project configuration.
    # Edit this file to configure your project.
    # ==============================================================================
    {
      enable = true;
      name = "my-project";
      github = "owner/repo";
      # debug = false;

      # ---------------------------------------------------------------------------
      # CLI - Stackpanel command-line tools
      # ---------------------------------------------------------------------------
      cli.enable = true;

      # ---------------------------------------------------------------------------
      # Theme - Starship prompt with stackpanel styling
      # See: https://stackpanel.dev/docs/theme
      # ---------------------------------------------------------------------------
      theme.enable = true;
      # theme = {
      #   name = "default";
      #   nerd-font = true;
      #   minimal = false;
      #
      #   colors = {
      #     primary = "#7aa2f7";
      #     secondary = "#bb9af7";
      #     success = "#9ece6a";
      #     warning = "#e0af68";
      #     error = "#f7768e";
      #     muted = "#565f89";
      #   };
      #
      #   starship = {
      #     add-newline = true;
      #     scan-timeout = 30;
      #     command-timeout = 500;
      #   };
      # };

      # ---------------------------------------------------------------------------
      # IDE Integration - Auto-generate editor config files
      # ---------------------------------------------------------------------------
      ide.enable = true;
      ide.vscode.enable = true;

      # ---------------------------------------------------------------------------
      # MOTD - Message of the day shown on shell entry
      # ---------------------------------------------------------------------------
      motd.enable = true;
      motd.commands = [
        {
          name = "dev";
          description = "Start development server";
        }
        {
          name = "build";
          description = "Build the project";
        }
      ];

      # ---------------------------------------------------------------------------
      # Users - Team members with project access
    # GitHub team members are auto-imported from data/github-collaborators.nix.
    # Add overrides or additional users here.
      # See: https://stackpanel.dev/docs/users
      # ---------------------------------------------------------------------------
      # users = {
      #   johndoe = {
      #     name = "John Doe";
      #     github = "johndoe";
      #     email = "john@example.com";
      #   };
      # };

      # ---------------------------------------------------------------------------
      # AWS - AWS Roles Anywhere for certificate-based authentication
      # See: https://stackpanel.dev/docs/aws
      # ---------------------------------------------------------------------------
      # aws = {
      #   roles-anywhere = {
      #     enable = true;
      #     region = "us-east-1";
      #     account-id = "123456789012";
      #     role-name = "DeveloperRole";
      #     trust-anchor-arn = "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/...";
      #     profile-arn = "arn:aws:rolesanywhere:us-east-1:123456789012:profile/...";
      #     cache-buffer-seconds = "300";
      #     prompt-on-shell = true;
      #   };
      # };

      # ---------------------------------------------------------------------------
      # Step CA - Internal certificate management for local HTTPS
      # See: https://stackpanel.dev/docs/step-ca
      # ---------------------------------------------------------------------------
      # step-ca = {
      #   enable = true;
      #   ca-url = "https://ca.internal:443";
      #   ca-fingerprint = "abc123...";  # Root CA fingerprint for verification
      #   provisioner = "admin";
      #   cert-name = "dev-workstation";
      #   prompt-on-shell = true;
      # };

      # ---------------------------------------------------------------------------
      # Secrets - Secrets management configuration
      # See: https://stackpanel.dev/docs/secrets
      # ---------------------------------------------------------------------------
      # secrets = {
      #   enable = true;
      #   input-directory = ".stack/secrets";
      #
      #   # Code generation for type-safe env access
      #   codegen = {
      #     typescript = {
      #       name = "env";
      #       directory = "packages/gen/env/src/generated";
      #       language = "typescript";
      #     };
      #   };
      # };

      # ---------------------------------------------------------------------------
      # SST - Infrastructure as code configuration
      # See: https://stackpanel.dev/docs/sst
      # ---------------------------------------------------------------------------
      # sst = {
      #   enable = true;
      #   project-name = "my-project";
      #   region = "us-west-2";
      #   account-id = "123456789012";
      #   config-path = "packages/infra/sst.config.ts";
      #
      #   kms = {
      #     enable = true;
      #     alias = "my-project-secrets";
      #   };
      #
      #   oidc = {
      #     provider = "github-actions";
      #     github-actions = {
      #       org = "my-org";
      #       repo = "*";
      #     };
      #   };
      # };

      # ---------------------------------------------------------------------------
      # Global Services - Shared development services
      # ---------------------------------------------------------------------------
      # globalServices = {
      #   enable = true;
      #   project-name = "myproject";
      #   postgres.enable = true;
      #   redis.enable = true;
      #   minio.enable = true;
      # };

      # ---------------------------------------------------------------------------
      # Caddy - Local HTTPS reverse proxy
      # ---------------------------------------------------------------------------
      # caddy = {
      #   enable = true;
      #   project-name = "myproject";
      # };
    }
  '';

  # ==========================================================================
  # .gitignore boilerplate
  # ==========================================================================
  gitignoreBoilerplate = ''
    # Runtime state (gitignored)
    state/

    # Local config overrides (per-user, gitignored)
    config.local.nix
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    # Root configuration message
    Config = proto.mkMessage {
      name = "Config";
      description = "Stackpanel project configuration";
      fields = {
        enable = proto.bool 1 "Enable stackpanel for this project";
        name = proto.string 2 "Project name";
        github = proto.string 3 "GitHub repository (owner/repo format)";
        debug = proto.bool 4 "Enable debug output";
      };
    };
  };
}
