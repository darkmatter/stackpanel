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
  # GitHub team members are auto-imported via _internal.nix.
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
  #   config = {
  #     enable = true;
  #     ca-url = "https://ca.internal:443";
  #     ca-fingerprint = "abc123...";  # Root CA fingerprint for verification
  #     provisioner = "admin";
  #     cert-name = "dev-workstation";
  #     prompt-on-shell = true;
  #   };
  # };

  # ---------------------------------------------------------------------------
  # Secrets - Secrets management configuration
  # See: https://stackpanel.dev/docs/secrets
  # ---------------------------------------------------------------------------
  # secrets = {
  #   enable = true;
  #
  #   # Directory containing SOPS-encrypted secrets (legacy layout)
  #   # Usually .stackpanel/secrets
  #   input-directory = ".stackpanel/secrets";
  #
  #   # Master keys for encrypting/decrypting secrets
  #   # Each secret specifies which master keys can decrypt it
  #   master-keys = {
  #     # Default local key - auto-generated, always works
  #     local = {
  #       age-pub = "age1...";  # computed from private key
  #       ref = "ref+file://.stackpanel/state/keys/local.txt";
  #     };
  #     
  #     # Team dev key - stored in AWS SSM
  #     dev = {
  #       age-pub = "age1...";
  #       ref = "ref+awsssm://stackpanel/keys/dev";
  #     };
  #     
  #     # Production key
  #     prod = {
  #       age-pub = "age1...";
  #       ref = "ref+awsssm://stackpanel/keys/prod";
  #     };
  #   };
  #
  #   # System-level AGE public keys (CI/deploy)
  #   system-keys = [
  #     # "age1..."
  #   ];
  #
  #   # Code generation targets for type-safe env access
  #   codegen = {
  #     typescript = {
  #       name = "env";
  #       directory = "packages/env/src/generated";
  #       language = "typescript";
  #     };
  #   };
  #
  #   # Environment-specific configs (SOPS sources + recipients)
  #   environments = {
  #     dev = {
  #       name = "dev";
  #       sources = [ "shared" "dev" ];
  #       public-keys = [
  #         "age1..."
  #       ];
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
  #     provider = "github-actions";  # or "flyio" or "roles-anywhere"
  #     github-actions = {
  #       org = "my-org";
  #       repo = "*";
  #     };
  #   };
  #
  #   iam = {
  #     role-name = "my-project-secrets-role";
  #   };
  # };

  # ---------------------------------------------------------------------------
  # Modules - Enable built-in modules or install from the registry
  # See: https://stackpanel.dev/docs/modules
  # ---------------------------------------------------------------------------
  # modules = {
  #   # Example: Enable the OxLint module
  #   oxlint = {
  #     enable = true;
  #   };
  #
  #   # Example: Configure a module with settings
  #   postgres = {
  #     enable = true;
  #     settings = {
  #       version = "16";
  #       port = "5432";
  #     };
  #   };
  # };

  # ---------------------------------------------------------------------------
  # STACKPANEL_MODULES_BEGIN
  # Auto-generated module configurations (do not edit this section manually)
  # Modules are sorted alphabetically and injected by the stackpanel CLI
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # STACKPANEL_MODULES_END
  # ---------------------------------------------------------------------------

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
