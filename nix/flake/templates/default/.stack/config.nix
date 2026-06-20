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

    # Suppress non-error CLI generation messages during shell entry. Useful in CI
    # or quiet direnv workflows where generated state, schemas, and IDE files
    # should update without printing progress logs.
    quiet = true;
  };

  # ----------------------------------------------------------------------------
  # Deploy
  # ----------------------------------------------------------------------------
  deploy = {
    # Base URL of the stackpanel cloud API. Override for self-hosted or staging
    # environments. The alchemy adapter reads this from STACKPANEL_API_URL at
    # deploy time.
    apiUrl = "https://staging-api.stackpanel.com";

    # Which backend alchemy uses for deploy state. - `local`: filesystem at
    # .alchemy/state/ (default). No network, no account, works offline. State
    # lives on whichever machine ran the deploy, so CI runners orphan resources
    # across runs. - `hosted`: api.stackpanel.com stores encrypted state per
    # organization. Survives runner churn, enables true team deploys, audited via
    # the studio's State panel. Requires an active Pro subscription.
    stateBackend = "hosted";
  };

  # ----------------------------------------------------------------------------
  # Devshell
  # ----------------------------------------------------------------------------
  devshell = {
    # Runtime libraries and packages exposed to builds that run inside the
    # devshell.
    buildInputs = [ pkgs.openssl pkgs.zlib ];

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
      impure = false;

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
];

      # Additional environment variables to keep for GUI applications. These are NOT
      # included by default. Add them to clean.keep if needed:
      # stackpanel.devshell.clean.keep = config.stackpanel.devshell.clean.keep ++
      # config.stackpanel.devshell.clean.keepGui;
      keepGui = [
  "DISPLAY"
  "WAYLAND_DISPLAY"
];

      # Environment variables for Warp terminal features. Add to clean.keep if using
      # Warp terminal.
      keepWarp = [
  "WARP_HONOR_PS1"
  "WARP_IS_LOCAL_SHELL_SESSION"
];

      # XDG base directory environment variables (often set by home-manager). Add to
      # clean.keep if you want to preserve these paths.
      keepXdg = [
  "XDG_CONFIG_HOME"
  "XDG_DATA_HOME"
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
    nativeBuildInputs = [ pkgs.pkg-config pkgs.cmake ];

    # Packages to add to the devshell (convenience wrapper over nativeBuildInputs
    # + buildInputs).
    packages = [
  "git"
  "ripgrep"
  "nodePackages.typescript"
]
;

    path = {
      # Directories to append to PATH in the devshell.
      append = [ ];

      # Directories to prepend to PATH in the devshell.
      prepend = [
  "./node_modules/.bin"
];
    };

    # If true, timing information will be printed during hook execution.
    timing = true;
  };

  # ----------------------------------------------------------------------------
  # Direnv
  # ----------------------------------------------------------------------------
  direnv = {
    # Hide direnv's environment diff log line when the user's direnv.toml supports
    # it.
    hide-env-diff = false;
  };

  # ----------------------------------------------------------------------------
  # Dirs
  # ----------------------------------------------------------------------------
  # Directory layout used by Stackpanel for config, keys, runtime profile, data,
  # and generated files.
  dirs = { # default: {
  home = ".stack";
}
    # Root directory for stackpanel files (relative to project root). This is the
    # ONLY configurable directory option. Subdirectories are automatically
    # computed: - keys/ (gitignored) - persistent credentials (AGE, AWS, step) -
    # profile/ (gitignored) - ephemeral runtime/cache (safe to rm) - gen/
    # (gitignored) - generated IDE configs, schemas - data/ (checked in) -
    # nix-backed configuration db Example: ".stack" → keys at ".stack/keys",
    # profile at ".stack/profile"
    home = ".config/stackpanel";
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
  # "/shared/cloudflare-account-id"; required = true; description = "Cloudflare
  # account ID used by deploy automation."; }; }; Module-contributed entries
  # merge cleanly with user-written ones thanks to NixOS submodule semantics
  # (declaring the same key from two places is a no-op as long as the values
  # agree). Codegen reads from this attrset to produce per-env SOPS payloads
  # under `<env-package>/data/_envs/<env>.sops.json` (one file per env,
  # encrypted to all recipients eligible for that env).
  envs = {
  # App-scoped (usually auto-populated):
  "apps/web/dev" = {
    DATABASE_URL = { secret = true; sops = "/dev/database-url"; required = true; };
    PORT         = { value = "3000"; required = true; };
    LOG_LEVEL    = { defaultValue = "info"; };
  };

  # Cross-cutting deploy-time secrets (declared by you and/or modules):
  deploy = {
    CLOUDFLARE_API_TOKEN  = { sops = "/shared/cloudflare-api-token"; required = true; };
    CLOUDFLARE_ACCOUNT_ID = { sops = "/shared/cloudflare-account-id"; required = true; };
    NEON_API_KEY          = { sops = "/shared/neon-api-key";          required = true; };
  };
}
;

  # ----------------------------------------------------------------------------
  # FlakeApps
  # ----------------------------------------------------------------------------
  # Flake apps to expose via `nix run .#<name>`. Each app must have: - type:
  # "app" - program: Path to executable (usually from a derivation)
  flakeApps = {
  web = {
    type = "app";
    program = "${packages.web}/bin/web";
  };
}
;

  # ----------------------------------------------------------------------------
  # Git-hooks
  # ----------------------------------------------------------------------------
  # Git hooks configuration fragment (consumed by git-hooks.nix).
  git-hooks = {
  pre-commit = {
    enable = true;
    stages = [ "pre-commit" ];
  };
}
;

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
    defaults = { # default: {
  localConfig = true;
  projectMarker = false;
  stackpanelState = true;
  tasksDir = true;
}
      # DEPRECATED: Use `stackpanel.gitignore.defaults.projectMarker` instead.
      # Backward-compatible alias for including `stackpanel.root-marker` in
      # `.gitignore`.
      addProjectMarker = false;

      # Include the machine-local Stackpanel config file in the managed `.gitignore`
      # block.
      localConfig = true;

      # Include the root marker file (`stackpanel.root-marker`) in the managed
      # `.gitignore` block.
      projectMarker = false;

      # Include the Stackpanel runtime state directory in the managed `.gitignore`
      # block.
      stackpanelState = true;

      # Include the generated `.tasks` directory in the managed `.gitignore` block.
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
      description = "Runs PostgreSQL as a local development database server";
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
    panels = [{
      id = "postgres-status";
      title = "PostgreSQL Status";
      type = "PANEL_TYPE_STATUS";
      fields = [{
        name = "metrics";
        type = "FIELD_TYPE_JSON";
        value = "[{\"label\":\"Status\",\"value\":\"Running\",\"status\":\"ok\"}]";
      }];
    }];
  };

  my-custom-module = {
    enable = true;
    meta = {
      name = "My Custom Module";
      description = "Adds project-specific development helpers";
      category = "development";
    };
    source = {
      type = "flake-input";
      flakeInput = "my-module";
    };
  };
}
;

  # ----------------------------------------------------------------------------
  # Name
  # ----------------------------------------------------------------------------
  # Name of your project. May be used for naming things and diplay purposes.
  name = "acme-storefront";

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
    # Project name used in generated metadata; defaults to stackpanel.name.
    name = "stackpanel";

    # Project source type used for repository-aware integrations.
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
    # Secret storage backend for writable `stackpanel.variables` scopes. This is
    # the single source of truth that controls where scoped variables are stored,
    # how entrypoints inject them, how the agent reads/writes them, and what
    # options are available in the UI. `/computed/*` variables are not stored
    # through this backend. They are read-only values produced by Nix modules and
    # exposed through the same variable registry for codegen/env consumers.
    # Backends: "sops" (default): direct SOPS/AGE encryption using `.sops.yaml`
    # files. "vals": legacy AGE/SOPS encryption with vals external references.
    # "chamber": AWS SSM Parameter Store via the chamber CLI. Scope examples:
    # `/dev/DATABASE_URL` -> dev scope `/prod/STRIPE_SECRET_KEY` -> prod scope
    # `/computed/apps/web/port` -> computed, read-only, no backend write
    backend = "sops";

    chamber = {
      # Chamber service prefix used when `stackpanel.secrets.backend = "chamber"`.
      # The full chamber service path is `{service-prefix}/{scope}`. For example,
      # with prefix "darkmatter/stackpanel" and variable `/dev/DATABASE_URL`:
      # chamber write darkmatter/stackpanel/dev DATABASE_URL <value> chamber exec
      # darkmatter/stackpanel/dev -- <command> With `/prod/STRIPE_SECRET_KEY`, the
      # service is `darkmatter/stackpanel/prod` and the chamber key is
      # `STRIPE_SECRET_KEY`. `/computed/*` variables never use chamber because they
      # are read-only Nix outputs, not stored secrets. Defaults to "{owner}/{repo}"
      # when project owner/repo are configured, otherwise falls back to the project
      # name.
      service-prefix = "darkmatter/stackpanel";
    };

    # Code generation targets keyed by name, such as `typescript` or `go`.
    # Generated helpers consume resolved variables and secret metadata; they do
    # not store plaintext secret values in Nix.
    codegen = {
  typescript = {
    directory = "packages/gen/env/src";
    language = "typescript";
    name = "env";
  };
};

    # SOPS creation rules rendered into the repo-root `.sops.yaml`. `path-regex`
    # is matched by SOPS against the encrypted file path. For grouped variables,
    # match files under `.stack/secrets/vars/`, such as
    # `.stack/secrets/vars/dev.sops.yaml` or `.stack/secrets/vars/prod.sops.yaml`.
    # Rules can reference direct recipient names, reusable recipient groups, and
    # optional KMS config from `stackpanel.secrets.kms.*`. Put narrower rules
    # before broader catch-all rules because SOPS applies the first match.
    creation-rules = [
  {
    path-regex = "^\\.stack/secrets/vars/dev\\.sops\\.yaml$";
    recipient-groups = [ "dev-team" ];
  }
  {
    path-regex = "^\\.stack/secrets/vars/prod\\.sops\\.yaml$";
    recipients = [ "deploy_bot" ];
    recipient-groups = [ "prod-admins" ];
    unencrypted-comment-regex = "^description$";
  }
]
;

    # Enable Stackpanel secret file management, recipient generation, and env
    # codegen
    enable = true;

    # Legacy environment-specific secrets configuration for source merging. New
    # variable definitions should use `stackpanel.variables` plus SOPS creation
    # rules instead.
    environments = {
  dev = {
    public-keys = [
      "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1"
    ];
    sources = [
      "shared"
      "dev"
    ];
  };
};

    # Deprecated legacy groups option.
    groups = { };

    # Legacy directory containing SOPS-encrypted source files used by
    # `environments.*.sources`.
    input-directory = ".stack/secrets";

    kms = {
      # Optional AWS profile name to pass alongside the KMS ARN in `.sops.yaml`.
      aws-profile = "production";

      # Optional AWS IAM role ARN for assume-role. Added to the SOPS KMS entry as
      # `role_arn` when set.
      aws-role-arn = "arn:aws:iam::123456789012:role/sops-decryptor";

      # AWS KMS key ARN to add as a SOPS recipient in the repo-root `.sops.yaml`.
      # When set, every creation rule will encrypt to this KMS key in addition to
      # the configured AGE recipients.
      key-arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-abc123";
    };

    # Legacy master keys for encrypting and decrypting individual `.age` secret
    # files. These keys are only used by older vals/.age flows such as wrapped
    # packages and `secrets:export`. They are separate from SOPS recipients used
    # for `vars/*.sops.yaml` and from the generated repo-root `.sops.yaml`. A
    # `local` key is configured by default. Its public key may be empty until
    # bootstrapping generates `.stack/keys/local.txt`; register real team or CI
    # keys here only when a legacy `.age` consumer still needs them.
    master-keys = {
  local = {
    age-pub = "age1localpublickeyexample0000000000000000000000000000000";
    ref = "ref+file://.stack/keys/local.txt";
  };
  ci = {
    age-pub = "age1cipublickeyexample000000000000000000000000000000000";
    ref = "ref+awsssm://stackpanel/ci/age-private-key";
  };
  prod = {
    age-pub = "age1prodpublickeyexample0000000000000000000000000000000";
    ref = "ref+vault://secret/data/stackpanel/prod#age_private_key";
    resolve-cmd = null;
  };
}
;

    # Reusable recipient sets that can be referenced by SOPS creation rules. Group
    # members are names from `stackpanel.secrets.recipients` or names derived from
    # `stackpanel.users`. Groups make environment rules compact and keep recipient
    # rotation in one place.
    recipient-groups = {
  dev-team.recipients = [ "alice" "bob" ];
  ci.recipients = [ "buildkite" ];
}
;

    # SOPS recipients declared in Nix. These entries are rendered into the
    # repo-root `.sops.yaml` and selected by `stackpanel.secrets.creation-rules`.
    # Keys may be native AGE recipients (`age1...`) or SSH Ed25519 public keys
    # (`ssh-ed25519 ...`). SSH keys are converted by SOPS at encryption time. Use
    # tags as human-readable environment or role metadata; creation rules select
    # explicit recipient names or recipient groups, not tags directly. If left
    # empty, Stackpanel falls back to recipients derived from
    # `stackpanel.users.*.public-keys` and `secrets-allowed-environments`.
    recipients = {
  cooper = {
    public-key = "age1psa52j93p0t7rej4lyzeww6hzg9hh4ylxu6v30tcgag44apw8als2xg3ef";
    tags = [ "dev" "prod" "shared" ];
  };
  coop_mac_studio = {
    public-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFauRe+VXvSmsca73hmxrylRPiueX/aHbXUu1jz7kGB8";
    tags = [ "dev" ];
  };
}
;

    # Secrets workspace directory (default: `.stack/secrets`). Grouped variables
    # are stored under `vars/<group>.sops.yaml` inside this directory. Legacy
    # `.age` files may also live here for older master-key based consumers.
    secrets-dir = ".stack/secrets";

    sops-age-keys = {
      # Optional `op://` references queried with `op read`. If configured,
      # `sops-age-keys` attempts these references after configured file paths.
      op-refs = [
  "op://travel/age-keys/local/private"
  "op://travel/age-keys/shared/private"
]
;

      # Additional private key file paths searched by `sops-age-keys` after
      # `user-key-path` and `repo-key-path`. Paths are tested with `[[ -f ]]` as
      # provided, so they can be absolute or relative to your current working
      # directory.
      paths = [
  "/tmp/team-keys/sops.age"
  "/run/secrets/ci.age"
]
;

      # Repo-local fallback AGE key path generated by Stackpanel for development.
      # This is convenient for bootstrapping, but a user-level or external key
      # source is preferred for long-term use.
      repo-key-path = "\".stack/keys/local.txt\"";

      # Ordered key sources tried by `sops-age-keys`. This is the preferred
      # configuration model for the UI. File-like sources are tried in order until
      # one yields an AGE private key. Non-file sources may resolve via SSH identity
      # conversion, macOS Keychain, AWS KMS, 1Password, vals, keyservice, or custom
      # scripts.
      sources = [
  {
    type = "user-key-path";
    value = "$HOME/Library/Application Support/sops/age/keys.txt";
    name = "User AGE key";
  }
  {
    type = "op-ref";
    value = "op://platform/sops-age/prod-private-key";
    account = "darkmatter";
  }
  {
    type = "script";
    value = "aws ssm get-parameter --with-decryption --name /stackpanel/sops-age --query Parameter.Value --output text";
    name = "CI SSM key";
  }
]
;

      # Primary user-level AGE key path for SOPS. This should point to a
      # user-managed key file outside the repo. Stackpanel checks this before any
      # additional custom paths.
      user-key-path = "\"$HOME/Library/Application Support/sops/age/keys.txt\"";
    };

    # Legacy system-level AGE public keys for older `.age` flows. For current
    # grouped SOPS files, model CI/deploy access as explicit recipients and
    # include them in the relevant creation rules.
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
    custom = {
  myModule = {
    generatedConfig = ".stack/gen/my-module/config.json";
    enabledApps = [ "web" "api" ];
  };
}
;

    # Devenv-related state for serialization. Populated by devenv integration
    # modules (services, languages, pre-commit). Structure: { services = {
    # available = [...]; enabled = [...]; }; languages = { available = [...];
    # enabled = [...]; }; preCommit = { available = [...]; enabled = [...]; }; }
    devenv = {
  services = {
    available = [ "postgres" "redis" ];
    enabled = [ "postgres" ];
  };
  languages = { available = [ "go" "javascript" ]; enabled = [ "go" ]; };
}
;

    # Name of the state file written to the state directory.
    file = "stackpanel-dev.json";
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
  # Workspace variable registry keyed by full variable ID. ID prefixes determine
  # ownership and storage: `/computed/*` - read-only values produced by Nix
  # modules `/<scope>/*` - writable, grouped variables stored in
  # `vars/<scope>.sops.yaml` Common writable scopes are `/dev/*`, `/staging/*`,
  # `/prod/*`, `/test/*`, and `/secret/*`, but scopes are just storage groups.
  # Non-computed values resolve to `var://<id>` markers by default; the grouped
  # SOPS file is the source of truth. Use SOPS creation rules such as
  # `^\.stack/secrets/vars/dev\.sops\.yaml$` to control recipients per scope.
  # Computed ids are reserved for Stackpanel modules. Examples include app
  # ports, app URLs, and service ports published as `/computed/apps/web/port`,
  # `/computed/apps/web/url`, and `/computed/services/postgres/port`.
  variables = {
  # Shared secret scope. Value lives in vars/secret.sops.yaml under key DATABASE_URL.
  "/secret/DATABASE_URL" = { };

  # Env-scoped groups. Same var name can differ per environment.
  "/dev/STRIPE_WEBHOOK_SECRET" = { };
  "/prod/STRIPE_WEBHOOK_SECRET" = { };

  # Explicit value is allowed, but most writable variables should stay empty
  # so they resolve through the encrypted scope file.
  "/test/API_BASE_URL" = { value = "http://localhost:3000"; };

  # Existing vals refs are accepted during migration.
  "/legacy/SMTP_PASSWORD" = { value = "ref+sops://legacy/smtp-password"; };

  # Computed variables are usually contributed by modules, not handwritten.
  "/computed/apps/web/port" = { value = "3000"; };
  "/computed/apps/web/url" = { value = "https://web.localhost"; };
}
;
}
