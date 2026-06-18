# ==============================================================================
# config.nix
#
# Stackpanel project configuration (starter).
# Generated from the current option schema.
#
# To see the latest options and examples (after upgrading stackpanel):
#   stack config generate --output .stack/config.nix.example
#
# Review the generated .example and copy/merge sections you need.
# ==============================================================================
{
  cli = {
    enable = true;
    quiet = false;
  };

  deploy = {
    apiUrl = "https://api.stackpanel.com";
    stateBackend = "local";
  };

  devshell = {
    buildInputs = [ ];
    clean = {
      aliases = [
        "dev"
        "start"
      ];
      enable = true;
      impure = true;
      keep = [
        "HOME"
        "USER"
        "SSH_AUTH_SOCK"
        "DISPLAY"
      ];
      keepDirenv = [
        "DIRENV_DIR"
        "DIRENV_FILE"
      ];
      keepFzf = [
        "FZF_DEFAULT_COMMAND"
        "FZF_DEFAULT_OPTS"
        "FZF_CTRL_T_COMMAND"
        "FZF_ALT_C_COMMAND"
      ];
      keepGui = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
        "XDG_RUNTIME_DIR"
        "DBUS_SESSION_BUS_ADDRESS"
      ];
      keepWarp = [
        "WARP_HONOR_PS1"
        "WARP_IS_LOCAL_SHELL_SESSION"
        "WARP_USE_SSH_WRAPPER"
      ];
      keepXdg = [
        "XDG_CACHE_HOME"
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
      ];
    };
    env = {
      MY_SERVICE_URL = "http://localhost:8080";
      NODE_ENV = "development";
    };
    hooks = {
      after = [ ];
      before = [ ];
      main = [
        "echo 'Welcome to the devshell for my-project'"
      ];
    };
    nativeBuildInputs = [ ];
    packages = [
      "git"
      "ripgrep"
      "nodePackages.typescript"
    ];
    path = {
      append = [ ];
      prepend = [
        "./node_modules/.bin"
      ];
    };
    timing = false;
  };

  direnv = {
    hide-env-diff = true;
  };

  dirs = {
    home = ".stack";
  };

  enable = true;

  envs = {
    # App-scoped (usually auto-populated):
    "apps/web/dev" = {
      DATABASE_URL = {
        secret = true;
        sops = "/dev/database-url";
        required = true;
      };
      PORT = {
        value = "3000";
        required = true;
      };
      LOG_LEVEL = {
        defaultValue = "info";
      };
    };

    # Cross-cutting deploy-time secrets (declared by you and/or modules):
    deploy = {
      CLOUDFLARE_API_TOKEN = {
        sops = "/shared/cloudflare-api-token";
        required = true;
      };
      CLOUDFLARE_ACCOUNT_ID = {
        sops = "/shared/cloudflare-account-id";
        required = true;
      };
      NEON_API_KEY = {
        sops = "/shared/neon-api-key";
        required = true;
      };
    };
  };

  flakeApps = {
    web = {
      type = "app";
      program = "./result/bin/web";
    };
  };

  git-hooks = {
    pre-commit = {
      enable = true;
      stages = [ "pre-commit" ];
    };
  };

  gitignore = {
    defaults = {
      addProjectMarker = false;
      localConfig = true;
      projectMarker = false;
      stackpanelState = true;
      tasksDir = true;
    };
    enable = true;
    entries = [
      "dist/"
      ".env.local"
      "result"
    ];
  };

  moduleRequirements = { };

  modules = {
    postgres = {
      enable = true;
      meta = {
        name = "PostgreSQL";
        description = "PostgreSQL database server";
        icon = "database";
        category = "database";
      };
      source.type = "builtin";
      features = {
        services = true;
        healthchecks = true;
        packages = true;
      };
      healthcheckModule = "postgres";
      panels = [
        {
          id = "postgres-status";
          title = "PostgreSQL Status";
          type = "PANEL_TYPE_STATUS";
          fields = [
            {
              name = "metrics";
              type = "FIELD_TYPE_JSON";
              value = "[{\"label\":\"Status\",\"value\":\"Running\",\"status\":\"ok\"}]";
            }
          ];
        }
      ];
    };

    my-custom-module = {
      enable = true;
      meta = {
        name = "My Custom Module";
        description = "Does something useful";
        category = "development";
      };
      source = {
        type = "flake-input";
        flakeInput = "my-module";
      };
    };
  };

  name = "my-project";

  panels = { };

  project = {
    name = "my-project";
    type = "github";
  };

  root-marker = ".stackpanel-root";

  secrets = {
    backend = "sops";
    chamber = {
      service-prefix = "my-project";
    };
    codegen = { };
    creation-rules = [
      {
        path-regex = "^dev/web\\.sops\\.yaml$";
        recipient-groups = [ "dev-team" ];
      }
    ];
    enable = true;
    environments = { };
    groups = { };
    input-directory = ".stack/secrets";
    kms = {
      aws-profile = "production";
      aws-role-arn = "arn:aws:iam::123456789012:role/sops-decryptor";
      key-arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-abc123";
    };
    master-keys = {
      local = {
        age-pub = "";
        ref = "ref+file://.stack/keys/local.txt";
      };
    };
    recipient-groups = {
      dev-team.recipients = [
        "alice"
        "bob"
      ];
      ci.recipients = [ "buildkite" ];
    };
    recipients = {
      cooper = {
        public-key = "age1psa52j93p0t7rej4lyzeww6hzg9hh4ylxu6v30tcgag44apw8als2xg3ef";
        tags = [
          "dev"
          "prod"
          "shared"
        ];
      };
      coop_mac_studio = {
        public-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFauRe+VXvSmsca73hmxrylRPiueX/aHbXUu1jz7kGB8";
        tags = [ "dev" ];
      };
    };
    secrets-dir = ".stack/secrets";
    sops-age-keys = {
      op-refs = [
        "op://travel/age-keys/local/private"
        "op://travel/age-keys/shared/private"
      ];
      paths = [
        "/tmp/team-keys/sops.age"
        "/run/secrets/ci.age"
      ];
      repo-key-path = "\".stack/keys/local.txt\"";
      sources = [
        {
          name = "User key path";
          type = "user-key-path";
          value = "$HOME/Library/Application Support/sops/age/keys.txt";
        }
        {
          name = "Repo key path";
          type = "repo-key-path";
          value = ".stack/keys/local.txt";
        }
      ];
      user-key-path = "\"$HOME/Library/Application Support/sops/age/keys.txt\"";
    };
    system-keys = "age1ci1234ci1234ci1234ci1234ci1234ci1234ci1234ci1234ci1";
  };

  serializable = {
    myModule = {
      count = 42;
      featureX = true;
    };
  };

  state = {
    custom = { };
    devenv = { };
    file = "stackpanel.json";
  };

  userPackages = {
    enable = true;
  };

  variables = {
    # Shared config (plaintext, NOT encrypted)
    "/var/LOG_LEVEL" = {
      value = "info";
    };
    "/var/API_VERSION" = {
      value = "v1";
    };

    # Grouped variable (value lives in vars/secret.sops.yaml under key postgres_url)
    "/secret/postgres-url" = {
      value = "";
    };

    # Env-scoped grouped variable (value lives in vars/dev.sops.yaml under key postgres_url)
    "/dev/postgres-url" = {
      value = "";
    };
  };
}
