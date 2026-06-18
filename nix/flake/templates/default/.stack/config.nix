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
  # ----------------------------------------------------------------------------
  # Cli
  # ----------------------------------------------------------------------------
  cli = {
    # Whether to enable CLI-based file generation.
    enable = true;

    # Suppress generation output messages
    quiet = false;
  };

  # ----------------------------------------------------------------------------
  # Deploy
  # ----------------------------------------------------------------------------
  deploy = {
    # Base URL of the stackpanel cloud API. Override for self-hosted or staging
    # environments. The alchemy adapter reads this from STACKPANEL_API_URL at
    # deploy time.
    apiUrl = "https://api.stackpanel.com";

    # Which backend alchemy uses for deploy state. - `local`: filesystem at
    # .alchemy/state/ (default). No network, no account, works offline. State
    # lives on whichever machine ran the deploy, so CI runners orphan resources
    # across runs. - `hosted`: api.stackpanel.com stores encrypted state per
    # organization. Survives runner churn, enables true team deploys, audited via
    # the studio's State panel. Requires an active Pro subscription.
    stateBackend = "local";
  };

  # ----------------------------------------------------------------------------
  # Devshell
  # ----------------------------------------------------------------------------
  devshell = {
    # Build inputs for the devshell.
    buildInputs = [ ];

    clean = {
      # List of shell aliases to unset when entering the devshell. Use this if you
      # have aliases that conflict with stackpanel scripts (e.g., "dev").
      aliases = [
        "dev"
        "start"
      ];

      # Whether to enable clean environment mode.
      enable = true;

      # Whether to use --impure flag when entering the devshell. --impure allows Nix
      # to access environment variables and system state, but prevents effective
      # caching between runs. Set to false if you want better caching and your
      # devshell doesn't need access to parent environment state.
      impure = true;

      # Environment variables to preserve when clean.enable is true. These variables
      # are passed through from the parent environment. Use `nix develop
      # --ignore-environment --impure` with `--keep` flags for each variable in this
      # list, or use the generated wrapper script.
      keep = [
        "HOME"
        "USER"
        "SSH_AUTH_SOCK"
        "DISPLAY"
      ];

      # Direnv state variables. Only needed if using direnv inside the clean shell.
      keepDirenv = [
        "DIRENV_DIR"
        "DIRENV_FILE"
      ];

      # Environment variables for fzf configuration. Add to clean.keep if you want
      # to preserve your fzf settings.
      keepFzf = [
        "FZF_DEFAULT_COMMAND"
        "FZF_DEFAULT_OPTS"
        "FZF_CTRL_T_COMMAND"
        "FZF_ALT_C_COMMAND"
      ];

      # Additional environment variables to keep for GUI applications. These are NOT
      # included by default. Add them to clean.keep if needed:
      # stackpanel.devshell.clean.keep = config.stackpanel.devshell.clean.keep ++
      # config.stackpanel.devshell.clean.keepGui;
      keepGui = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
        "XDG_RUNTIME_DIR"
        "DBUS_SESSION_BUS_ADDRESS"
      ];

      # Environment variables for Warp terminal features. Add to clean.keep if using
      # Warp terminal.
      keepWarp = [
        "WARP_HONOR_PS1"
        "WARP_IS_LOCAL_SHELL_SESSION"
        "WARP_USE_SSH_WRAPPER"
      ];

      # XDG base directory environment variables (often set by home-manager). Add to
      # clean.keep if you want to preserve these paths.
      keepXdg = [
        "XDG_CACHE_HOME"
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
      ];
    };

    # Environment variables to set in the devshell.
    env = {
      MY_SERVICE_URL = "http://localhost:8080";
      NODE_ENV = "development";
    };

    hooks = {
      # Commands to run after the main devshell setup (e.g. final PATH tweaks).
      after = [ ];

      # Shell commands to run early when entering the devshell (before other setup).
      before = [ ];

      # Main shell initialization commands (e.g. starting services or printing
      # hints).
      main = [
        "echo 'Welcome to the devshell for my-project'"
      ];
    };

    # Native build inputs for the devshell (tools needed to build, not necessarily
    # at runtime).
    nativeBuildInputs = [ ];

    # Packages to add to the devshell (convenience wrapper over nativeBuildInputs
    # + buildInputs).
    packages = [
      "git"
      "ripgrep"
      "nodePackages.typescript"
    ];

    path = {
      # Directories to append to PATH in the devshell.
      append = [ ];

      # Directories to prepend to PATH in the devshell.
      prepend = [
        "./node_modules/.bin"
      ];
    };

    # If true, timing information will be printed during hook execution.
    timing = false;
  };

  # ----------------------------------------------------------------------------
  # Direnv
  # ----------------------------------------------------------------------------
  direnv = {
    # Hide the 'direnv: export +VAR...' log line (requires user's direnv.toml)
    hide-env-diff = true;
  };

  # ----------------------------------------------------------------------------
  # Dirs
  # ----------------------------------------------------------------------------
  # Directories used by stackpanel.
  dirs = {
    # Root directory for stackpanel files (relative to project root). This is the
    # ONLY configurable directory option. Subdirectories are automatically
    # computed: - keys/ (gitignored) - persistent credentials (AGE, AWS, step) -
    # profile/ (gitignored) - ephemeral runtime/cache (safe to rm) - gen/
    # (gitignored) - generated IDE configs, schemas - data/ (checked in) -
    # nix-backed configuration db Example: ".stack" → keys at ".stack/keys",
    # profile at ".stack/profile"
    home = ".stack";
  };

  # ----------------------------------------------------------------------------
  # Enable
  # ----------------------------------------------------------------------------
  # Whether to enable Enable Stackpanel.
  enable = true;

  # ----------------------------------------------------------------------------
  # Envs
  # ----------------------------------------------------------------------------
  # Environment variables grouped by scope name. Three usage patterns: 1.
  # App-scoped (auto-populated). Each app's `apps.<app>.env` is exploded into
  # one entry per environment ID, keyed `apps/<app>/<env>`:
  # `stackpanel.envs."apps/web/dev".DATABASE_URL = { ... };` You don't write
  # these directly — they're contributed by env-codegen. 2. Cross-cutting
  # scopes (you write these). A bare scope name like `deploy`, `infra`, or `ci`
  # is meant for variables that are not tied to any single app:
  # `stackpanel.envs.deploy.CLOUDFLARE_API_TOKEN = { sops = "..."; };` Loaded at
  # runtime via `loadEnvScope("deploy")` (see
  # `packages/gen/env/src/runtime/loader.ts`). 3. Module-contributed (modules
  # write these). Stackpanel modules can declare envs they need by writing to
  # `stackpanel.envs.<scope>` from their own `config = { ... };`. For example, a
  # Cloudflare deployment module that's only enabled when an app sets
  # `deployment.host = "cloudflare"` can do: config.stackpanel.envs.deploy =
  # lib.mkIf hasCloudflareApp { CLOUDFLARE_ACCOUNT_ID = { sops =
  # "/shared/cloudflare-account-id"; required = true; description = "..."; }; };
  # Module-contributed entries merge cleanly with user-written ones thanks to
  # NixOS submodule semantics (declaring the same key from two places is a no-op
  # as long as the values agree). Codegen reads from this attrset to produce
  # per-env SOPS payloads under `<env-package>/data/_envs/<env>.sops.json` (one
  # file per env, encrypted to all recipients eligible for that env).
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

  # ----------------------------------------------------------------------------
  # FlakeApps
  # ----------------------------------------------------------------------------
  # Flake apps to expose via `nix run .#<name>`. Each app must have: - type:
  # "app" - program: Path to executable (usually from a derivation)
  flakeApps = {
    web = {
      type = "app";
      program = "./result/bin/web";
    };
  };

  # ----------------------------------------------------------------------------
  # Git-hooks
  # ----------------------------------------------------------------------------
  # Git hooks configuration fragment (consumed by git-hooks.nix).
  git-hooks = {
    pre-commit = {
      enable = true;
      stages = [ "pre-commit" ];
    };
  };

  # ----------------------------------------------------------------------------
  # Gitignore
  # ----------------------------------------------------------------------------
  # Reserved options for managed `.gitignore` generation. Stackpanel core owns a
  # block-managed section in `.gitignore` and merges entries from this option.
  # This provides a stable, explicit API for common `.gitignore` presets while
  # still allowing modules to contribute entries. The generated block is
  # deduplicated and sorted.
  gitignore = {
    # Toggle built-in `.gitignore` presets managed by Stackpanel.
    defaults = {
      # DEPRECATED: Use `stackpanel.gitignore.defaults.projectMarker` instead.
      # Backward-compatible alias for including `stackpanel.root-marker` in
      # `.gitignore`.
      addProjectMarker = false;

      # Include `.stack/config.local.nix`.
      localConfig = true;

      # Include the root marker file (`stackpanel.root-marker`).
      projectMarker = false;

      # Include `.stack/state/`.
      stackpanelState = true;

      # Include `.tasks`.
      tasksDir = true;
    };

    # Whether Stackpanel should manage a `.gitignore` block.
    enable = true;

    # Additional `.gitignore` entries to include in the managed block.
    entries = [
      "dist/"
      ".env.local"
      "result"
    ];
  };

  # ----------------------------------------------------------------------------
  # ModuleRequirements
  # ----------------------------------------------------------------------------
  # Variable requirements declared by enabled modules. Modules add entries here
  # to declare what environment variables they need. The agent/UI can query this
  # to show what's missing. Format: { moduleName = { requires = [ ... ];
  # provides = [ ... ]; }; }
  moduleRequirements = { };

  # ----------------------------------------------------------------------------
  # Modules
  # ----------------------------------------------------------------------------
  # Stackpanel modules that provide features and UI panels. Modules are the
  # unified way to extend stackpanel functionality: - Add packages, scripts, and
  # environment configuration - Generate files and manage secrets - Define
  # health checks and background services - Provide UI panels for the web studio
  # - Extend per-app configuration Each module can define: - `enable`: Whether
  # the module is active - `meta`: Display metadata (name, description, icon,
  # category) - `source`: Where the module comes from (builtin, local,
  # flake-input, registry) - `features`: Which stackpanel systems it uses -
  # `panels`: UI panels to render in the web studio - `configSchema`: JSON
  # Schema for configuration form generation - `healthcheckModule`: Link to
  # health checks Modules can be: - Builtin: Shipped with stackpanel - Local:
  # Defined in your project - Remote: Installed via flake inputs or module
  # registry
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

  # ----------------------------------------------------------------------------
  # Name
  # ----------------------------------------------------------------------------
  # Name of your project. May be used for naming things and diplay purposes.
  name = "my-project";

  # ----------------------------------------------------------------------------
  # Panels
  # ----------------------------------------------------------------------------
  # UI panels for core Stackpanel modules. Panels are UI components that display
  # information about a module's state, configuration, or managed resources.
  # Unlike extension panels, these belong to built-in modules like Go, Caddy,
  # Healthchecks, etc. Example: stackpanel.panels.go-status = { module = "go";
  # title = "Go Environment"; type = "PANEL_TYPE_STATUS"; order = 10; fields = [
  # { name = "metrics"; type = "FIELD_TYPE_STRING"; value = "..."; } ]; };
  panels = { };

  # ----------------------------------------------------------------------------
  # Project
  # ----------------------------------------------------------------------------
  # Project metadata including type, owner, and repository information.
  project = {
    # Project name (defaults to stackpanel.name)
    name = "my-project";

    # Project type (e.g., 'github', 'gitlab', 'local')
    type = "github";
  };

  # ----------------------------------------------------------------------------
  # Root-marker
  # ----------------------------------------------------------------------------
  # Filename for the root marker file written to the project root. Contains the
  # absolute path to the project root, allowing tools to find the project from
  # any subdirectory. Add to .dockerignore and .gitignore so containers create
  # their own marker.
  root-marker = ".stackpanel-root";

  # ----------------------------------------------------------------------------
  # Secrets
  # ----------------------------------------------------------------------------
  secrets = {
    # Secret storage backend. This is the single source of truth that controls how
    # secrets are stored, how entrypoints inject them, how the agent reads/writes
    # them, and what options are available in the UI. "sops" (default): direct
    # SOPS/AGE encryption using generated `.sops.yaml` files. "vals": legacy
    # AGE/SOPS encryption with vals for external references. "chamber": AWS SSM
    # Parameter Store via the chamber CLI.
    backend = "sops";

    chamber = {
      # Chamber service prefix. The full chamber service path is:
      # {service-prefix}/{env} For example, with prefix "darkmatter/stackpanel" and
      # a variable /dev/DATABASE_URL: chamber write darkmatter/stackpanel/dev
      # DATABASE_URL <value> chamber exec darkmatter/stackpanel/dev -- <command>
      # Defaults to "{owner}/{repo}" when project owner/repo are configured,
      # otherwise falls back to the project name.
      service-prefix = "my-project";
    };

    # Code generation targets keyed by name (e.g., typescript, go, python). Used
    # to drive language-specific env/secret helpers.
    codegen = { };

    # SOPS creation rules rendered into `.stack/secrets/.sops.yaml`. These rules
    # mirror SOPS directly and can reference both direct recipients and reusable
    # recipient groups.
    creation-rules = [
      {
        path-regex = "^dev/web\\.sops\\.yaml$";
        recipient-groups = [ "dev-team" ];
      }
    ];

    # Enable secrets management
    enable = true;

    # Legacy environment-specific secrets configuration.
    environments = { };

    # Deprecated legacy groups option.
    groups = { };

    # Directory containing SOPS-encrypted secrets (legacy SOPS layout). Used when
    # decrypting/merging YAML sources defined under environments.
    input-directory = ".stack/secrets";

    kms = {
      # Optional AWS profile name to pass alongside the KMS ARN in `.sops.yaml`.
      aws-profile = "production";

      # Optional AWS IAM role ARN for assume-role. Added to the SOPS KMS entry as
      # `role_arn` when set.
      aws-role-arn = "arn:aws:iam::123456789012:role/sops-decryptor";

      # AWS KMS key ARN to add as a SOPS recipient in `.stack/secrets/.sops.yaml`.
      # When set, every creation rule will encrypt to this KMS key in addition to
      # the configured AGE recipients.
      key-arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-abc123";
    };

    # Master keys for encrypting and decrypting individual `.age` secret files.
    # These are separate from the SOPS recipient list used for `vars/*.sops.yaml`.
    # A default local key is always configured so local development works out of
    # the box.
    master-keys = {
      local = {
        age-pub = "";
        ref = "ref+file://.stack/keys/local.txt";
      };
    };

    # Reusable recipient sets that can be referenced by SOPS creation rules.
    recipient-groups = {
      dev-team.recipients = [
        "alice"
        "bob"
      ];
      ci.recipients = [ "buildkite" ];
    };

    # SOPS recipients declared in Nix. These entries are rendered into
    # `.stack/secrets/.sops.yaml`. If left empty, Stackpanel falls back to
    # recipients derived from `stackpanel.users.*.public-keys` and
    # `secrets-allowed-environments`.
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

    # Directory where secret .age files are stored (default: .stack/secrets)
    secrets-dir = ".stack/secrets";

    sops-age-keys = {
      # Optional `op://` references queried with `op read`. If configured,
      # `sops-age-keys` attempts these references after configured file paths.
      op-refs = [
        "op://travel/age-keys/local/private"
        "op://travel/age-keys/shared/private"
      ];

      # Additional private key file paths searched by `sops-age-keys` after
      # `user-key-path` and `repo-key-path`. Paths are tested with `[[ -f ]]` as
      # provided, so they can be absolute or relative to your current working
      # directory.
      paths = [
        "/tmp/team-keys/sops.age"
        "/run/secrets/ci.age"
      ];

      # Repo-local fallback AGE key path generated by Stackpanel for development.
      # This is convenient for bootstrapping, but a user-level or external key
      # source is preferred for long-term use.
      repo-key-path = "\".stack/keys/local.txt\"";

      # Ordered key sources tried by `sops-age-keys`. This is the preferred
      # configuration model for the UI. File-like sources are tried in order until
      # one yields an AGE private key.
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

      # Primary user-level AGE key path for SOPS. This should point to a
      # user-managed key file outside the repo. Stackpanel checks this before any
      # additional custom paths.
      user-key-path = "\"$HOME/Library/Application Support/sops/age/keys.txt\"";
    };

    # System-level AGE public keys (CI, deploy servers, etc.). These keys can
    # decrypt all secrets regardless of environment restrictions.
    system-keys = "age1ci1234ci1234ci1234ci1234ci1234ci1234ci1234ci1234ci1";
  };

  # ----------------------------------------------------------------------------
  # Serializable
  # ----------------------------------------------------------------------------
  # Serializable configuration data for the agent and CLI. Modules can
  # contribute their JSON-safe config here. This data is included in
  # stackpanelConfig for external tools.
  serializable = {
    myModule = {
      count = 42;
      featureX = true;
    };
  };

  # ----------------------------------------------------------------------------
  # State
  # ----------------------------------------------------------------------------
  state = {
    # Arbitrary state data contributed by modules. Use this for module-specific
    # state that should be serialized.
    custom = { };

    # Devenv-related state for serialization. Populated by devenv integration
    # modules (services, languages, pre-commit). Structure: { services = {
    # available = [...]; enabled = [...]; }; languages = { available = [...];
    # enabled = [...]; }; preCommit = { available = [...]; enabled = [...]; }; }
    devenv = { };

    # Name of the state file written to the state directory.
    file = "stackpanel.json";
  };

  # ----------------------------------------------------------------------------
  # UserPackages
  # ----------------------------------------------------------------------------
  userPackages = {
    # Whether to enable user-installed packages from .stack/data/packages.nix.
    enable = true;
  };

  # ----------------------------------------------------------------------------
  # Variables
  # ----------------------------------------------------------------------------
  # Workspace variables keyed by their full variable ID. Prefixes determine
  # storage: /computed/* - Nix-computed values (read-only) /* - Grouped
  # SOPS-backed variables stored in `vars/<prefix>.sops.yaml` Non-computed
  # variable values resolve to variable-link markers; the group SOPS file is the
  # source of truth.
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
