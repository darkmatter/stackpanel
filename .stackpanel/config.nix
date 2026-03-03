# ==============================================================================
# config.nix
#
# Stackpanel project configuration.
# Both human-editable and machine-editable (single source of truth).
#
# Machine writes will sort keys alphabetically and format with nixfmt.
# For config that needs pkgs/lib (computed values, custom packages),
# use .stackpanel/modules/ which has full NixOS module context.
# ==============================================================================
{
  # ---------------------------------------------------------------------------
  # Apps
  # ---------------------------------------------------------------------------
  apps = {
    docs = {
      bun.enable = true;
      bun.generateFiles = false;
      bun.buildPhase = "bun run build";
      bun.startScript = "bun serve.ts";
      description = "Documentation site";
      domain = "docs";
      environments = {
        dev = {
          env = {
            PORT = "ref+sops://.stackpanel/secrets/computed.yaml#/apps/docs/port";
          };
          name = "dev";
        };
        prod = {
          env = { };
          name = "prod";
        };
        staging = {
          env = { };
          name = "staging";
        };
      };
      linting = {
        oxlint = {
          enable = true;
        };
      };
      name = "docs";
      path = "apps/docs";
      type = "bun";
    };
    stackpanel-go = {
      description = "Stackpanel CLI and agent (Go)";
      environments = {
        dev = {
          env = {
            STACKPANEL_TEST_PAIRING_TOKEN = "token123";
          };
          name = "dev";
        };
      };
      go = {
        binaryName = "stackpanel";
        enable = true;
        generateFiles = false;
        ldflags = [
          "-s"
          "-w"
        ];
      };
      name = "stackpanel";
      path = "apps/stackpanel-go";
      type = "go";
    };
    web = {
      bun.enable = true;
      bun.generateFiles = false;
      bun.buildPhase = "bun run build:fly";
      commands = {
        dev = {
          command = "bun run -F web dev";
        };
      };
      container = {
        enable = true;
        type = "bun";
      };
      framework.tanstack-start.enable = true;
      deployment = {
        enable = true;
        host = "cloudflare";
        bindings = [
          "DATABASE_URL"
          "CORS_ORIGIN"
          "BETTER_AUTH_SECRET"
          "BETTER_AUTH_URL"
          "POLAR_ACCESS_TOKEN"
          "POLAR_SUCCESS_URL"
        ];
        secrets = [
          "DATABASE_URL"
          "BETTER_AUTH_SECRET"
          "POLAR_ACCESS_TOKEN"
        ];
      };
      description = "Main web application";
      domain = "stackpanel";
      environments = {
        dev = {
          env = {
            APP_HOST = "ref+sops://.stackpanel/secrets/computed.yaml#/apps/web/url";
            MEMO_MEMOAS_AD = "foobar";
            OPENAI_API_KEY = "ref+sops://packages/gen/env/data/web/dev.yaml#/OPENAI_API_KEY";
            PORT = "ref+sops://.stackpanel/secrets/computed.yaml#/apps/web/port";
            POSTGRES_URL = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL";
          };
          name = "dev";
        };
        prod = {
          env = {
            OPENAI_API_KEY = "ref+sops://packages/gen/env/data/web/prod.yaml#/OPENAI_API_KEY";
          };
          name = "prod";
        };
        staging = {
          env = { };
          name = "staging";
        };
      };
      linting = {
        oxlint = {
          categories = {
            correctness = "error";
            suspicious = "warn";
          };
          enable = true;
          fix = true;
          plugins = [
            "react"
            "typescript"
          ];
        };
      };
      name = "web";
      path = "apps/web";
      tls = true;
      type = "bun";
    };
  };

  # ---------------------------------------------------------------------------
  # AWS
  # ---------------------------------------------------------------------------
  aws = {
    roles-anywhere = {
      account-id = "950224716579";
      enable = true;
      profile-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:profile/4e72b392-9074-4e53-8cd0-1ba50856d1ca";
      region = "us-west-2";
      role-name = "darkmatter-dev";
      trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:trust-anchor/c99a9383-6be1-48ba-8e63-c3ab6b7069cb";
    };
  };

  # ---------------------------------------------------------------------------
  # Binary Cache
  # ---------------------------------------------------------------------------
  binary-cache = {
    cachix = {
      cache = "darkmatter";
      enable = false;
    };
    enable = true;
  };

  # ---------------------------------------------------------------------------
  # Caddy
  # ---------------------------------------------------------------------------
  caddy = {
    enable = true;
    project-name = "stackpanel";
    use-step-tls = true;
  };

  # ---------------------------------------------------------------------------
  # CLI
  # ---------------------------------------------------------------------------
  cli = {
    enable = true;
  };

  # ---------------------------------------------------------------------------
  # Containers
  # ---------------------------------------------------------------------------
  containers = {
    settings = {
      backend = "nix2container";
    };
    # Linux builder detection and fallback for macOS users
    builder = {
      enable = true;
      warnIfMissing = true;
      # Remote builder fallback for team members without Determinate Nix native builder
      remote = {
        enable = true;
        host = "100.102.113.26";
        user = "root";
        sshKeyPath = "/etc/nix/builder_ed25519";
        systems = [ "x86_64-linux" ];
        maxJobs = 16;
        speedFactor = 1;
        supportedFeatures = [
          "big-parallel"
          "benchmark"
          "kvm"
          "nixos-test"
        ];
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Debug
  # ---------------------------------------------------------------------------
  debug = false;

  # ---------------------------------------------------------------------------
  # Deployment
  # ---------------------------------------------------------------------------
  deployment = {
    fly = {
      organization = "darkmatter";
    };
  };

  # ---------------------------------------------------------------------------
  # Devshell
  # ---------------------------------------------------------------------------
  devshell = {
    clean = {
      impure = false;
    };
    hooks = {
      main = [
        ''
          echo "Stackpanel development environment"
        ''
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Project
  # ---------------------------------------------------------------------------
  enable = true;

  # ---------------------------------------------------------------------------
  # Env Codegen
  # ---------------------------------------------------------------------------
  env.package-name = "@gen/env";

  # ---------------------------------------------------------------------------
  # Git Hooks
  # ---------------------------------------------------------------------------
  git-hooks = {
    enable = true;
  };

  # ---------------------------------------------------------------------------
  # GitHub
  # ---------------------------------------------------------------------------
  github = "darkmatter/stackpanel";

  # ---------------------------------------------------------------------------
  # Global Services
  # ---------------------------------------------------------------------------
  globalServices = {
    caddy = {
      enable = true;
    };
    enable = true;
    minio = {
      enable = true;
    };
    postgres = {
      databases = [
        "stackpanel"
        "stackpanel_test"
      ];
      enable = true;
    };
    project-name = "stackpanel";
    redis = {
      enable = true;
    };
  };

  # ---------------------------------------------------------------------------
  # IDE
  # ---------------------------------------------------------------------------
  ide = {
    enable = true;
    vscode = {
      enable = true;
      extensions = [
        "ms-azuretools.vscode-docker"
        "golang.go"
      ];
      extra-folders = [ ];
      output-mode = "settingsJson";
    };
    zed = {
      enable = true;
      output-mode = "generated";
    };
  };

  # ---------------------------------------------------------------------------
  # MOTD
  # ---------------------------------------------------------------------------
  motd = {
    enable = true;
    hints = [
      "Run './test' to test both devenv and native shells"
      "Run './test devenv' or './test native' to test individual shells"
      "Run 'nix flake check --impure' to run all checks including smoke tests"
    ];
  };

  # ---------------------------------------------------------------------------
  # Name
  # ---------------------------------------------------------------------------
  name = "stackpanel";

  # ---------------------------------------------------------------------------
  # Packages (resolved to nixpkgs by the module system)
  # ---------------------------------------------------------------------------
  packages = [
    "sops"
    "air"
    "buf"
    "git"
    "go"
    "gomod2nix"
    "jq"
    "nixd"
    "nixfmt"
    "oxfmt"
    "oxlint"
    "quicktype"
  ];

  # ---------------------------------------------------------------------------
  # Ports
  # ---------------------------------------------------------------------------
  ports = {
    services = {
      MINIO = {
        name = "Minio";
      };
      MINIO_CONSOLE = {
        name = "Minio Console";
      };
      POSTGRES = {
        name = "PostgreSQL";
      };
      REDIS = {
        name = "Redis";
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Secrets
  # ---------------------------------------------------------------------------
  secrets = {
    backend = "chamber";
    codegen = {
      typescript = {
        directory = "packages/gen/env/src/generated";
        language = "CODEGEN_LANGUAGE_TYPESCRIPT";
        name = "env";
      };
    };
    enable = true;
    environments = { };
    secrets-dir = ".stackpanel/secrets";
    system-keys = [ ];
  };

  # ---------------------------------------------------------------------------
  # SST
  # ---------------------------------------------------------------------------
  sst = {
    account-id = "950224716579";
    config-path = "packages/infra/sst.config.ts";
    enable = true;
    iam = {
      role-name = "stackpanel-secrets-role";
    };
    kms = {
      alias = "stackpanel-secrets";
      deletion-window-days = 30;
      enable = true;
    };
    oidc = {
      flyio = {
        app-name = "*";
        org-id = "";
      };
      github-actions = {
        branch = "*";
        org = "darkmatter";
        repo = "stackpanel";
      };
      provider = "github-actions";
      roles-anywhere = {
        trust-anchor-arn = "";
      };
    };
    project-name = "stackpanel";
    region = "us-west-2";
  };

  # ---------------------------------------------------------------------------
  # Step CA
  # ---------------------------------------------------------------------------
  step-ca = {
    ca-fingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
    ca-url = "https://ca.internal:443";
    cert-name = "device";
    enable = true;
    prompt-on-shell = true;
    provisioner = "Authentik";
  };

  # ---------------------------------------------------------------------------
  # Tasks
  # ---------------------------------------------------------------------------
  tasks = {
    build = {
      description = "Build all packages and apps";
      env = { };
      exec = "turbo run build";
    };
    clean = {
      description = "Clean build artifacts and caches";
      env = { };
      exec = "turbo run clean && rm -rf node_modules/.cache";
    };
    "db:migrate" = {
      cwd = "apps/server";
      description = "Run database migrations";
      env = { };
      exec = "bun run drizzle-kit migrate";
    };
    "db:push" = {
      cwd = "apps/server";
      description = "Push schema changes to database";
      env = { };
      exec = "bun run drizzle-kit push";
    };
    "db:studio" = {
      cwd = "apps/server";
      description = "Open Drizzle Studio database GUI";
      env = { };
      exec = "bun run drizzle-kit studio";
    };
    dev = {
      cache = false;
      description = "Start all development servers";
      env = { };
      exec = "turbo run dev";
    };
    format = {
      description = "Format all code";
      env = { };
      exec = "bun run prettier --write .";
    };
    "generate:proto" = {
      cwd = "packages/proto";
      description = "Generate TypeScript and Go types from proto schemas";
      env = { };
      exec = "./generate.sh";
    };
    "generate:types" = {
      description = "Generate TypeScript types from Nix schemas";
      env = { };
      exec = "./nix/stackpanel/core/generate-types.sh";
    };
    lint = {
      description = "Run linter across all packages";
      env = { };
      exec = "turbo run lint";
    };
    test = {
      description = "Run all tests";
      env = { };
      exec = "turbo run test";
    };
    "test:coverage" = {
      description = "Run tests with coverage report";
      env = { };
      exec = "turbo run test:coverage";
    };
    "test:watch" = {
      description = "Run tests in watch mode";
      env = { };
      exec = "turbo run test:watch";
    };
    typecheck = {
      description = "Run TypeScript type checker";
      env = { };
      exec = "turbo run typecheck";
    };
  };

  # ---------------------------------------------------------------------------
  # Theme
  # ---------------------------------------------------------------------------
  theme = {
    enable = true;
    preset = "stackpanel";
  };

  # ---------------------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------------------
  users = {
    cooper = {
      github = "coopmoney";
      name = "Cooper Maruyama";
      public-keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINh0gA7reCRW+zQ5pPpIjoJGpaFQSbC/4K8B6vMXJVr+ cooper@darkmatter.io"
      ];
      secrets-allowed-environments = [
        "web/dev"
        "web/staging"
        "web/production"
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Variables
  # ---------------------------------------------------------------------------
  variables = {
    "/common/SHARED_VALUE" = {
      id = "/common/SHARED_VALUE";
      value = "secret value";
    };
    "/dev/OPENAI_API_KEY" = {
      value = "ref+sops://.stackpanel/secrets/dev.yaml#/OPENAI_API_KEY";
    };
    "/foobar" = {
      id = "/foobar";
      key = "foobar";
      type = "SECRET";
      value = "";
    };
    "/my-api-endpoint" = {
      id = "/my-api-endpoint";
      key = "my-api-endpoint";
      type = "SECRET";
      value = "cool-api.com";
    };
    "/prod/POSTGRES_URL" = {
      value = "ref+sops://.stackpanel/secrets/prod.yaml#/POSTGRES_URL";
    };
    "/secret-foo" = {
      id = "/secret-foo";
      key = "secret-foo";
      type = "SECRET";
      value = "";
    };
    "/stripe-secre-key" = {
      id = "/stripe-secre-key";
      value = "ref+sops://.stackpanel/secrets/common.yaml#/KEY";
    };
    "/test" = {
      id = "/test";
      key = "test";
      type = "SECRET";
      value = "";
    };
    "/username" = {
      id = "/username";
      key = "username";
      type = "SECRET";
      value = "";
    };
    "/var/API_VERSION" = {
      value = "v1";
    };
    "/var/LOG_LEVEL" = {
      value = "info";
    };
  };
}
