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
      description = "Documentation site";
      domain = "docs";
      environments = {
        dev = {
          env = { };
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
      tls = true;
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
      commands = {
        dev = {
          command = "bun run -F web dev";
        };
      };
      container = {
        enable = true;
        type = "bun";
      };
      deployment = {
        bindings = [
          "DATABASE_URL"
          "CORS_ORIGIN"
          "BETTER_AUTH_SECRET"
          "BETTER_AUTH_URL"
          "POLAR_ACCESS_TOKEN"
          "POLAR_SUCCESS_URL"
        ];
        enable = true;
        fly = {
          appName = "stackpanel-web";
          region = "iad";
        };
        host = "fly";
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
            MEMO_MEMOAS_AD = "foobar";
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
      framework = {
        tanstack-start = {
          enable = true;
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
    tld = "lan";
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
    builder = {
      enable = true;
      remote = {
        enable = true;
        host = "100.102.113.26";
        maxJobs = 16;
        speedFactor = 1;
        sshKeyPath = "/etc/nix/builder_ed25519";
        supportedFeatures = [
          "big-parallel"
          "benchmark"
          "kvm"
          "nixos-test"
        ];
        systems = [ "x86_64-linux" ];
        user = "root";
      };
      warnIfMissing = true;
    };
    settings = {
      backend = "nix2container";
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

  env = {
    package-name = "@gen/env";
  };

  files = {
    entries = {
      ".gitignore" = {
        dedupe = true;
        lines = [
          "node_modules"
          ".stackpanel/bin"
          "dist"
          "build"
          "*.tsbuildinfo"
          ".stackpanel/.token"
          ".env"
          ".env*.local"
          ".idea"
          "*.swp"
          "*.swo"
          "*~"
          ".DS_Store"
          "logs"
          "*.log"
          "*.tgz"
          ".cache"
          "tmp"
          "temp"
          ".devenv"
          ".devenv.flake.nix"
          "devenv.local.nix"
          "devenv.local.yaml"
          ".direnv"
          "/.stackpanel/state"
          "/.devenv*"
          "/.devenv-root"
          "/result"
          ".stackpanel/state/"
        ];
        managed = "block";
        sort = true;
        type = "line-set";
      };
    };
  };

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
      output-mode = "dotZed";
    };
  };

  infra = {
    aws-ec2-app = {
      apps = {
        stackpanel-staging = {
          ami = null;
          associate-public-ip = true;
          iam = {
            enable = true;
            role-name = "stackpanel-staging-ec2-role";
          };
          instance-count = 2;
          instance-type = "t3.micro";
          instances = [ ];
          key-name = null;
          key-pair = {
            create = true;
            name = "stackpanel-staging-key";
            public-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPg7wQoa2hMfuz9f9CLJNVY2z8iQD7EFlJk+sBztnIhe";
          };
          machine = {
            arch = null;
            roles = [
              "docs"
              "web"
            ];
            ssh = {
              key-path = null;
              port = 22;
              user = "root";
            };
            tags = [ "staging" ];
            target-env = "staging";
          };
          os-type = "nixos";
          root-volume-size = null;
          security-group = {
            create = true;
            description = null;
            egress = [
              {
                cidr-blocks = [ "0.0.0.0/0" ];
                description = "All outbound";
                from-port = 0;
                protocol = "-1";
                to-port = 0;
              }
            ];
            ingress = [
              {
                cidr-blocks = [ "0.0.0.0/0" ];
                description = "SSH";
                from-port = 22;
                protocol = "tcp";
                to-port = 22;
              }
              {
                cidr-blocks = [ "0.0.0.0/0" ];
                description = "HTTP";
                from-port = 80;
                protocol = "tcp";
                to-port = 80;
              }
              {
                cidr-blocks = [ "0.0.0.0/0" ];
                description = "HTTPS";
                from-port = 443;
                protocol = "tcp";
                to-port = 443;
              }
            ];
            name = null;
          };
          security-group-ids = [ ];
          subnet-ids = [ ];
          tags = {
            ManagedBy = "stackpanel-infra";
            Name = "stackpanel-staging";
          };
          user-data = null;
          vpc-id = null;
        };
      };
      defaults = { };
      enable = true;
    };
    database = {
      enable = true;
      neon = {
        api-key-ssm-path = "/common/neon-api-key";
        region = "aws-us-east-1";
      };
      provider = "neon";
    };
    enable = true;
    machines = {
      aws = {
        filters = [
          {
            name = "instance-state-name";
            values = [ "running" ];
          }
        ];
        region = "us-west-2";
      };
      enable = true;
      machines = { };
      source = "aws-ec2";
    };
    storage-backend = {
      sops = {
        group = "dev";
      };
      type = "sops";
    };
  };

  languages = {
    go = {
      enable = true;
    };
    javascript = {
      bun = {
        enable = true;
        install = {
          enable = true;
        };
      };
      enable = true;
    };
    typescript = {
      enable = true;
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
  # Packages
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
    groups = {
      dev = {
        age-pub = "age1783kahlc7yxv2md9vtpx4wq899csvqxty03fatcs5s7lqfh5334s6p7r0l";
      };
      prod = {
        age-pub = "age1tvczw6y7g4v0ma7cn05adrnst9jnnsh9j8ge0t0flls8ucq5yg9qe37jhe";
      };
    };
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
    "alchemy:ensure" = {
      description = "Ensure alchemy is initialized - builds will error without this if using alchemy for deployments. creates wrangler.jsonc when using @cloudflare/vite-plugin";
      env = { };
      exec = "test -f .alchemy/local/wrangler.jsonc || (mkdir -p .alchemy/local && echo '{\"name\":\"web\",\"main\":\".alchemy/local/worker.js\",\"compatibility_date\":\"2025-01-01\",\"assets\":{\"directory\":\"dist\"}}' > .alchemy/local/wrangler.jsonc)";
    };
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
    "/dev/openrouter-api-key" = {
      id = "/dev/openrouter-api-key";
      value = "";
    };
    "/dev/test-api-key" = {
      id = "/dev/test-api-key";
      value = "";
    };
    "/var/web-hostname-staging" = {
      id = "/var/web-hostname-staging";
      value = "staging.stackpanel.dev";
    };
  };

}

