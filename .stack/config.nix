# ==============================================================================
# config.nix
#
# Stackpanel project configuration.
# Both human-editable and machine-editable (single source of truth).
#
# Machine writes will sort keys alphabetically and format with nixfmt.
# For config that needs pkgs/lib (computed values, custom packages),
# use .stack/nix/ (or .stackpanel/nix/) which has full NixOS module context.
# ==============================================================================
{config, ...}: {
  alchemy = {
    deploy = {
      enable = true;
    };
  };

  portless = {
    enable = true;
    project-name = "stackpanel";
    tld = "lan";
  };

  # ---------------------------------------------------------------------------
  # Apps
  # ---------------------------------------------------------------------------
  apps = {
    docs = {
      bun = {
        generateFiles = false;
      };
      description = "Documentation site";
      deployment = {
        enable = true;
        backend = "colmena";
        targets = ["stackpanel-test"];
        command = "bun serve.ts";
        cloudflare = {
          workerName = "stackpanel-docs";
        };
        host = "cloudflare";
        modules = [
          {
            networking.firewall.allowedTCPPorts = [3000];
          }
        ];
      };
      domain = "docs";
      environments = {
        shared = {
          env = {
            PORT = "var://computed/apps/docs/port";
          };
          name = "shared";
        };
        dev = {
          env = {
            PORT = "var://computed/apps/docs/port";
            HOSTNAME = "stackpanel.lan";
          };
          name = "dev";
          extends = ["common"];
        };
        prod = {
          env = {};
          name = "prod";
        };
        staging = {
          env = {
          };
          name = "staging";
        };
        test = {
          env = {
            POSTGRES_URL = config.variables."/test/postgres-url".value;
          };
          name = "test";
        };
      };
      framework = {
        nextjs = {
          enable = true;
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
      bun = {
        enable = true;
        buildPhase = "./node_modules/.bin/vite build";
        startScript = "node .output/server/index.mjs";
        generateFiles = false;
      };
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
        aws = {
          region = "us-west-2";
          os-type = "nixos";
        };
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
        host = "aws";
        secrets = [
          "DATABASE_URL"
          "BETTER_AUTH_SECRET"
          "POLAR_ACCESS_TOKEN"
        ];
      };
      description = "Main web application";
      domain = "@";
      environments = {
        dev = {
          env = {
            BETTER_AUTH_SECRET = "";
            BETTER_AUTH_URL = "";
            CORS_ORIGIN = "";
            POLAR_ACCESS_TOKEN = "";
            POLAR_SUCCESS_URL = "";
            POSTGRES_URL = "var://secret/postgres-url";
          };
          name = "dev";
        };
        prod = {
          env = {
            BETTER_AUTH_SECRET = "";
            BETTER_AUTH_URL = "";
            CORS_ORIGIN = "";
            POLAR_ACCESS_TOKEN = "";
            POLAR_SUCCESS_URL = "";
            POSTGRES_URL = "var://secret/postgres-url";
          };
          name = "prod";
        };
        staging = {
          env = {
            BETTER_AUTH_SECRET = "";
            BETTER_AUTH_URL = "";
            CORS_ORIGIN = "";
            POLAR_ACCESS_TOKEN = "";
            POLAR_SUCCESS_URL = "";
            POSTGRES_URL = "var://secret/postgres-url";
          };
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

  aws-vault = {
    awsProfiles = {
      sso-prod = {
        extraConfig = {
          sso_account_id = "950224716579";
          sso_region = "us-east-1";
          sso_role_name = "admin-profile";
          sso_start_url = "https://dark-matter.awsapps.com/start";
        };
        output = "json";
        region = "us-east-1";
      };
      sso-staging = {
        extraConfig = {
          sso_account_id = "123456789012";
          sso_region = "us-east-1";
          sso_role_name = "StagingAccess";
          sso_start_url = "https://dark-matter.awsapps.com/start";
        };
        output = "json";
        region = "us-east-1";
      };
    };
    awscliWrapper = {
      enable = true;
    };
    enable = false;
    profiles = [
      "sso-prod"
      "sso-staging"
    ];
    showProfileAttempts = true;
    stopOnFirstSuccess = true;
    terraformWrapper = {
      enable = true;
    };
  };

  # ---------------------------------------------------------------------------
  # Binary Cache
  # ---------------------------------------------------------------------------
  binary-cache = {
    cachix = {
      cache = "darkmatter";
      enable = true;
    };
    enable = true;
  };

  # ---------------------------------------------------------------------------
  # Colmena
  # ---------------------------------------------------------------------------
  colmena = {
    enable = true;
    substituteOnDestination = true;
    flake = ".";
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
        systems = ["x86_64-linux"];
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
    aws = {
      instance-type = "t3.small";
      region = "us-west-2";
    };
    fly = {
      organization = "darkmatter";
    };
    machines = {
      volt-1 = {
        host = "10.0.100.11";
        user = "root";
        system = "x86_64-linux";
        proxyJump = "root@runner-hz-hel-slate";
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+M/DHDlKgayM6wsiX6r704pE+2qENOsKcytC7sBhKA"
        ];
      };
      volt-2 = {
        host = "10.0.100.12";
        user = "root";
        system = "x86_64-linux";
        proxyJump = "root@runner-hz-hel-slate";
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+M/DHDlKgayM6wsiX6r704pE+2qENOsKcytC7sBhKA"
        ];
      };
      volt-3 = {
        host = "10.0.100.13";
        user = "root";
        system = "x86_64-linux";
        proxyJump = "root@runner-hz-hel-slate";
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+M/DHDlKgayM6wsiX6r704pE+2qENOsKcytC7sBhKA"
        ];
      };
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
    references = {
      docs = {
        dev = {
          HELLO = "/secret/cool-secre";
          POSTGRES_URL = "/dev/postgres-url";
        };
        shared = {
          HELLO = "/secret/cool-secre";
          POSTGRES_URL = "/dev/postgres-url";
        };
      };
    };
  };

  files = {
    entries = {
      ".gitignore" = {
        dedupe = true;
        lines = [
          "node_modules"
          ".stack/bin"
          "dist"
          "build"
          "*.tsbuildinfo"
          ".stack/.token"
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
          "/.stack/state"
          "/.devenv*"
          "/.devenv-root"
          "/result"
          ".stack/state/"
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
      extra-folders = [];
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
        docs = {
          ami = null;
          associate-public-ip = true;
          iam = {
            enable = true;
            role-name = "docs-ec2-role";
          };
          instance-count = 1;
          instance-type = "t3.micro";
          instances = [];
          key-name = null;
          key-pair = {
            create = false;
            name = null;
            public-key = null;
          };
          machine = {
            arch = null;
            roles = ["docs"];
            ssh = {
              key-path = null;
              port = 22;
              user = "root";
            };
            tags = [];
            target-env = "staging";
          };
          os-type = "nixos";
          root-volume-size = null;
          security-group = {
            create = true;
            description = null;
            egress = [
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "All outbound";
                from-port = 0;
                protocol = "-1";
                to-port = 0;
              }
            ];
            ingress = [
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "SSH";
                from-port = 22;
                protocol = "tcp";
                to-port = 22;
              }
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "HTTP";
                from-port = 80;
                protocol = "tcp";
                to-port = 80;
              }
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "HTTPS";
                from-port = 443;
                protocol = "tcp";
                to-port = 443;
              }
            ];
            name = null;
          };
          security-group-ids = [];
          subnet-ids = [];
          tags = {
            ManagedBy = "stackpanel-infra";
            Name = "docs";
          };
          user-data = null;
          vpc-id = null;
        };
        stackpanel-staging = {
          ami = null;
          associate-public-ip = true;
          iam = {
            enable = true;
            role-name = "stackpanel-staging-ec2-role";
          };
          instance-count = 1;
          instance-type = "t2.micro";
          instances = [];
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
            tags = ["staging"];
            target-env = "staging";
          };
          os-type = "nixos";
          root-volume-size = null;
          security-group = {
            create = true;
            description = null;
            egress = [
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "All outbound";
                from-port = 0;
                protocol = "-1";
                to-port = 0;
              }
            ];
            ingress = [
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "SSH";
                from-port = 22;
                protocol = "tcp";
                to-port = 22;
              }
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "HTTP";
                from-port = 80;
                protocol = "tcp";
                to-port = 80;
              }
              {
                cidr-blocks = ["0.0.0.0/0"];
                description = "HTTPS";
                from-port = 443;
                protocol = "tcp";
                to-port = 443;
              }
            ];
            name = null;
          };
          security-group-ids = [];
          subnet-ids = ["subnet-0a79923f197e60d02"];
          tags = {
            ManagedBy = "stackpanel-infra";
            Name = "stackpanel-staging";
          };
          user-data = null;
          vpc-id = null;
        };
      };
      defaults = {};
      enable = true;
    };
    database = {
      enable = true;
      neon = {
        api-key-ssm-path = "/common/neon-api-key";
        region = "aws-us-east-1";
      };
      provider = "auto";
    };
    enable = true;
    machines = {
      aws = {
        filters = [
          {
            name = "instance-state-name";
            values = ["running"];
          }
        ];
        region = "us-west-2";
      };
      enable = true;
      machines = {};
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

  project = {
    owner = "darkmatter";
    repo = "stackpanel";
  };

  # ---------------------------------------------------------------------------
  # Secrets
  # ---------------------------------------------------------------------------
  secrets = {
    backend = "sops";
    codegen = {
      typescript = {
        directory = "packages/gen/env/src";
        language = "CODEGEN_LANGUAGE_TYPESCRIPT";
        name = "env";
      };
    };
    creation-rules = [
      {
        path-regex = ".*";
        recipient-groups = ["everyone"];
        recipients = [];
      }
    ];
    enable = true;
    environments = {};
    groups = {
      dev = {};
      prod = {};
      test = {};
    };
    recipient-groups = let
      ghdata = import ./data/external/github-collaborators.nix;
    in {
      github-team = {
        recipients = builtins.attrNames ghdata.collaborators;
      };
      everyone = {
        recipients = [
          "arximboldi"
          "arximboldi_2"
          "arximboldi_3"
          "callumelvidge"
          "callumelvidge_2"
          "CasLinden"
          "CasLinden_2"
          "cooper"
          "coopmoney"
          "coopmoney_2"
          "coopmoney_3"
          "coopmoney_4"
          "fkb032"
          "jjkoh95"
          "scottmcmaster"
          "scottmcmaster_2"
        ];
      };
    };
    recipients = {
      keyservice = {
        public-key = "age16wuzuxnkcgfuxzvzgk5e5a5f6hhs386adjewyv54m9esr4yj6uuslpn6tp";
        tags = [
          "dev"
          "staging"
        ];
      };
      local = {
        public-key = "age16rkvks3tljju3y6xu0l7luhjzx634et97g3xe58xf2dgfn2865rqkq6t8f";
        tags = ["dev"];
      };
      github-actions = {
        public-key = "age1eqcj2g0fdekj2wpqp4y0fg9c5myydjdt9zlr5scr0grk6fxszymqkpw5jf";
        tags = [
          "dev"
          "staging"
          "production"
        ];
      };
    };
    secrets-dir = ".stack/secrets";
    sops-age-keys = {
      op-refs = [];
      paths = [];
      repo-key-path = ".stack/keys/local.txt";
      sources = [
        {
          enabled = true;
          id = "w9nmu0oca";
          name = "Repo Key Path";
          priority = 0;
          type = "repo-key-path";
          value = ".stack/keys/local.txt";
        }
        {
          enabled = true;
          id = "da2z16rpb";
          name = "User Key Path";
          priority = 1;
          type = "user-key-path";
          value = "~/.config/sops/age/keys.txt";
        }
        {
          enabled = true;
          id = "dojq058ew";
          name = "SSH Private Key";
          priority = 2;
          type = "ssh-key";
          value = "~/.ssh/id_ed25519";
        }
        {
          enabled = true;
          id = "hncecqshi";
          name = "SOPS Keyservice";
          priority = 3;
          type = "keyservice";
          value = "tcp://100.116.189.36:5000";
        }
      ];
      user-key-path = "\$XDG_CONFIG_HOME/sops/age/keys.txt";
    };
    system-keys = [];
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
      env = {};
      exec = "test -f .alchemy/local/wrangler.jsonc || (mkdir -p .alchemy/local && echo '{\"name\":\"web\",\"main\":\".alchemy/local/worker.js\",\"compatibility_date\":\"2025-01-01\",\"assets\":{\"directory\":\"dist\"}}' > .alchemy/local/wrangler.jsonc)";
    };
    build = {
      description = "Build all packages and apps";
      env = {};
      exec = "turbo run build";
    };
    clean = {
      description = "Clean build artifacts and caches";
      env = {};
      exec = "turbo run clean && rm -rf node_modules/.cache";
    };
    "db:migrate" = {
      cwd = "apps/server";
      description = "Run database migrations";
      env = {};
      exec = "bun run drizzle-kit migrate";
    };
    "db:push" = {
      cwd = "apps/server";
      description = "Push schema changes to database";
      env = {};
      exec = "bun run drizzle-kit push";
    };
    "db:studio" = {
      cwd = "apps/server";
      description = "Open Drizzle Studio database GUI";
      env = {};
      exec = "bun run drizzle-kit studio";
    };
    dev = {
      cache = false;
      description = "Start all development servers";
      env = {};
      exec = "turbo run dev";
    };
    format = {
      description = "Format all code";
      env = {};
      exec = "bun run prettier --write .";
    };
    "generate:proto" = {
      cwd = "packages/proto";
      description = "Generate TypeScript and Go types from proto schemas";
      env = {};
      exec = "./generate.sh";
    };
    "generate:types" = {
      description = "Generate TypeScript types from Nix schemas";
      env = {};
      exec = "./nix/stackpanel/core/generate-types.sh";
    };
    lint = {
      description = "Run linter across all packages";
      env = {};
      exec = "turbo run lint";
    };
    test = {
      description = "Run all tests";
      env = {};
      exec = "turbo run test";
    };
    "test:coverage" = {
      description = "Run tests with coverage report";
      env = {};
      exec = "turbo run test:coverage";
    };
    "test:watch" = {
      description = "Run tests in watch mode";
      env = {};
      exec = "turbo run test:watch";
    };
    typecheck = {
      description = "Run TypeScript type checker";
      env = {};
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
    "/secret/allvar" = {
      value = "";
    };
    "/secret/cool" = {
      value = "";
    };
    "/secret/cool-secre" = {
      value = "";
    };
    "/secret/openrouter-api-key" = {
      value = "";
    };
    "/secret/postgres-url" = {
      value = "";
    };
    "/secret/test-api-key" = {
      value = "";
    };
    "/var/web-hostname-staging" = {
      value = "staging.stackpanel.dev";
    };
    "/dev/postgres-url" = {
      value = "";
    };
    "/test/postgres-url" = {
      value = "";
    };
  };
}
