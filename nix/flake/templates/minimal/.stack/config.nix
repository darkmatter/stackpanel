# ==============================================================================
# config.nix
#
# Stackpanel project configuration (starter).
# Generated from the current option schema.
#
# To see the latest options and examples (after upgrading stackpanel):
#   stack config generate --output .stack/config.example.nix
#
# Review the generated .example and copy/merge sections you need.
# ==============================================================================
{
  cli = {
    enable = true;
    quiet = true;
  };

  deploy = {
    apiUrl = "https://staging-api.stackpanel.com";
    stateBackend = "hosted";
  };

  devshell = {
    buildInputs = [ pkgs.openssl pkgs.zlib ];
    clean = {
      aliases = [
  "dev"
  "start"
];
      enable = true;
      impure = false;
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
];
      keepGui = [
  "DISPLAY"
  "WAYLAND_DISPLAY"
];
      keepWarp = [
  "WARP_HONOR_PS1"
  "WARP_IS_LOCAL_SHELL_SESSION"
];
      keepXdg = [
  "XDG_CONFIG_HOME"
  "XDG_DATA_HOME"
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
    nativeBuildInputs = [ pkgs.pkg-config pkgs.cmake ];
    packages = [
  "git"
  "ripgrep"
  "nodePackages.typescript"
]
;
    path = {
      append = [ ];
      prepend = [
  "./node_modules/.bin"
];
    };
    timing = true;
  };

  direnv = {
    hide-env-diff = false;
  };

  dirs = { # default: {
  home = ".stack";
}
    home = ".config/stackpanel";
  };

  enable = true;

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

  flakeApps = {
  web = {
    type = "app";
    program = "${packages.web}/bin/web";
  };
}
;

  git-hooks = {
  pre-commit = {
    enable = true;
    stages = [ "pre-commit" ];
  };
}
;

  gitignore = {
    defaults = { # default: {
  localConfig = true;
  projectMarker = false;
  stackpanelState = true;
  tasksDir = true;
}
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

  name = "acme-storefront";

  panels = { };

  project = {
    name = "stackpanel";
    type = "github";
  };

  root-marker = ".stackpanel-root";

  secrets = {
    backend = "sops";
    chamber = {
      service-prefix = "darkmatter/stackpanel";
    };
    codegen = {
  typescript = {
    directory = "packages/gen/env/src";
    language = "typescript";
    name = "env";
  };
};
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
    enable = true;
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
    groups = { };
    input-directory = ".stack/secrets";
    kms = {
      aws-profile = "production";
      aws-role-arn = "arn:aws:iam::123456789012:role/sops-decryptor";
      key-arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-abc123";
    };
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
    recipient-groups = {
  dev-team.recipients = [ "alice" "bob" ];
  ci.recipients = [ "buildkite" ];
}
;
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
    secrets-dir = ".stack/secrets";
    sops-age-keys = {
      op-refs = [
  "op://travel/age-keys/local/private"
  "op://travel/age-keys/shared/private"
]
;
      paths = [
  "/tmp/team-keys/sops.age"
  "/run/secrets/ci.age"
]
;
      repo-key-path = "\".stack/keys/local.txt\"";
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
    custom = {
  myModule = {
    generatedConfig = ".stack/gen/my-module/config.json";
    enabledApps = [ "web" "api" ];
  };
}
;
    devenv = {
  services = {
    available = [ "postgres" "redis" ];
    enabled = [ "postgres" ];
  };
  languages = { available = [ "go" "javascript" ]; enabled = [ "go" ]; };
}
;
    file = "stackpanel-dev.json";
  };

  userPackages = {
    enable = true;
  };

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
