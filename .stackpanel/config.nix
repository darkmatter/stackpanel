# ==============================================================================
# config.nix
#
# Stackpanel project configuration.
# Edit this file to configure your project.
#
# For advanced features (lib.mkIf, config access, etc.), use ./modules/
# which are evaluated with full NixOS module context.
# ==============================================================================
{ pkgs }:
{
  # NOTE: Modules in ./modules/ are automatically loaded with full module context.
  # Use them for scripts, outputs, and conditional configuration.
  
  enable = true;
  name = "stackpanel";
  github = "darkmatter/stackpanel";
  debug = true;

  # ---------------------------------------------------------------------------
  # Theme & IDE
  # ---------------------------------------------------------------------------
  theme.enable = true;
  ide.enable = true;
  cli.enable = true;

  ide.vscode = {
    enable = true;
    extensions = [
      "ms-azuretools.vscode-docker"
      "golang.go"
    ];
    extra-folders = [ ];
  };

  # ---------------------------------------------------------------------------
  # Devshell Packages
  # ---------------------------------------------------------------------------
  packages = with pkgs; [
    air
    nixd
    git
    jq
    go
    gomod2nix
    quicktype
    prek
    buf
  ];

  # ---------------------------------------------------------------------------
  # AWS Roles Anywhere
  # ---------------------------------------------------------------------------
  aws.roles-anywhere = {
    enable = true;
    region = "us-west-2";
    account-id = "950224716579";
    role-name = "darkmatter-dev";
    trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:trust-anchor/c99a9383-6be1-48ba-8e63-c3ab6b7069cb";
    profile-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:profile/4e72b392-9074-4e53-8cd0-1ba50856d1ca";
  };

  # ---------------------------------------------------------------------------
  # Step CA
  # ---------------------------------------------------------------------------
  step-ca = {
    enable = true;
    ca-url = "https://ca.internal:443";
    ca-fingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
    provisioner = "Authentik";
    prompt-on-shell = true;
    cert-name = "device";
  };

  # ---------------------------------------------------------------------------
  # MOTD (Message of the Day)
  # ---------------------------------------------------------------------------
  motd.enable = true;
  motd.commands = [
    {
      name = "aws-creds-env";
      description = "Export AWS credentials to environment";
    }
  ];
  motd.hints = [
    "Run './test' to test both devenv and native shells"
    "Run './test devenv' or './test native' to test individual shells"
    "Run 'nix flake check --impure' to run all checks including smoke tests"
  ];

  # ---------------------------------------------------------------------------
  # Devshell Hooks
  # ---------------------------------------------------------------------------
  devshell.hooks.main = [
    ''
      echo "✅ Stackpanel development environment"
    ''
  ];

  # ---------------------------------------------------------------------------
  # Git Hooks
  # ---------------------------------------------------------------------------
  git-hooks = {
    enable = true;
  };

  # ---------------------------------------------------------------------------
  # Extensions
  # ---------------------------------------------------------------------------
  example = {
    enable = true;
    message = "Welcome to Stackpanel!";
  };

  caddy = {
    enable = true;
    project-name = "stackpanel";
  };

  # ---------------------------------------------------------------------------
  # Apps
  # ---------------------------------------------------------------------------
  apps.web = {
    name = "web";
    domain = "stackpanel";
    tls = true;
    # Environments with secrets configuration
    environments = {
      dev = {
        name = "dev";
        sources = [ "shared" "dev" ];
        public-keys = [ "age1..." ];
      };
      staging = {
        name = "staging";
        sources = [ "shared" "staging" ];
        public-keys = [ "age1..." ];
      };
      production = {
        name = "production";
        sources = [ "shared" "production" ];
        public-keys = [ "age1..." ];
      };
    };
  };
  apps.server = {
    name = "server";
  };
  apps.docs = {
    name = "docs";
    domain = "docs";
  };
  apps.stackpanel-go = {
    name = "stackpanel";
    path = "apps/stackpanel-go";
    go = {
      enable = true;
      binaryName = "stackpanel";
      ldflags = [
        "-s"
        "-w"
      ];
      generateFiles = false;
    };
  };

  # ---------------------------------------------------------------------------
  # Ports - Infrastructure Service Ports
  # ---------------------------------------------------------------------------
  ports.services = {
    POSTGRES = {
      name = "PostgreSQL";
    };
    REDIS = {
      name = "Redis";
    };
    MINIO = {
      name = "Minio";
    };
    MINIO_CONSOLE = {
      name = "Minio Console";
    };
  };

  # ---------------------------------------------------------------------------
  # Global Services
  # ---------------------------------------------------------------------------
  globalServices = {
    enable = true;
    project-name = "stackpanel";

    postgres = {
      enable = true;
      databases = [
        "stackpanel"
        "stackpanel_test"
      ];
      package = pkgs.postgresql_17;
    };

    redis.enable = true;
    minio.enable = true;
    caddy.enable = true;
  };

  # ---------------------------------------------------------------------------
  # Users
  # GitHub team members are auto-imported via _internal.nix.
  # Add overrides or additional users here.
  # ---------------------------------------------------------------------------
  users = {
    cooper = {
      name = "Cooper Maruyama";
      github = "coopmoney";
      public-keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINh0gA7reCRW+zQ5pPpIjoJGpaFQSbC/4K8B6vMXJVr+ cooper@darkmatter.io"
      ];
      # Environments are now "<app>/<env>" format, derived from apps.<app>.environments
      secrets-allowed-environments = [
        "web/dev"
        "web/staging"
        "web/production"
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Secrets
  # ---------------------------------------------------------------------------
  secrets = {
    # Directory for SOPS-encrypted environment YAML files
    # These files (shared.yaml, dev.yaml, etc.) are generated from:
    #   - .stackpanel/secrets/vars/*.age (agenix secrets)
    #   - .stackpanel/data/variables.nix (variable definitions)
    input-directory = ".stackpanel/secrets";
    
    # NOTE: environments are now defined in apps.<app>.environments
    # The secrets module computes environmentsComputed from apps automatically.
  };
}
