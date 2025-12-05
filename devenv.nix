{
  pkgs,
  lib,
  config,
  _inputs,
  ...
}:
let
  # Packages in ./tooling/nix are also impored
  # Equivalent to "devDependencies"
  devPackages = [
    pkgs.ripgrep
    pkgs.gnugrep
    pkgs.gum
    pkgs.jq
    pkgs.yq
    pkgs.nil
		pkgs.sops
  ];
in
{
  # https://devenv.sh/basics/
  # https://devenv.sh/reference/options/#env
  env = {
    STARSHIP_CONFIG = "${config.git.root}/nix/extra/starship.toml";
    COMPOSE_DOCKER_CLI_BUILD = "1";
    DOCKER_BUILDKIT = "1";

    # Mitigate Biome stack overflows by reducing Rayon threads and increasing stack size
    # Applies to Biome runs via treefmt and git hooks in this shell
    RAYON_NUM_THREADS = "1";
    RUST_MIN_STACK = "4194304"; # 4 MiB
  };

  # https://devenv.sh/packages/
  packages =
    with pkgs;
    devPackages
    # only if we're NOT in CI
    ++ lib.optionals (config.devenv.profile != "ci") [
      git
      starship
      bash
      postgresql
      direnv
      lefthook
      # docker
      # docker-compose
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      apple-sdk_15
    ];

  # https://devenv.sh/reference/options/#profiles
  profiles.ci = {
    module =
      { pkgs, ... }:
      {
        packages =
          devPackages
          ++ lib.optionals pkgs.stdenv.isDarwin [
            pkgs.apple-sdk_15
          ];
        enterShell = lib.mkForce ''
          echo "Loaded profile: ci"
        '';
      };
  };

  # https://devenv.sh/languages/
  # https://devenv.sh/supported-languages/javascript/
  # JavaScript/Node.js - provide defaults that apps can override
  languages.javascript.enable = lib.mkDefault true;
  languages.javascript.package = lib.mkDefault pkgs.nodejs_24;
  languages.javascript.corepack.enable = lib.mkDefault true;
  languages.javascript.pnpm.enable = lib.mkDefault true;
  languages.javascript.pnpm.install.enable = lib.mkDefault true;

  languages.nix.enable = true;

  # https://devenv.sh/processes/
  # https://devenv.sh/reference/options/#processes
  processes.db-studio.exec = "${pkgs.pnpm}/bin/pnpm db:studio";
  processes.metro.exec = "${pkgs.pnpm}/bin/pnpm -F @acme/expo dev";
  processes.metro.process-compose.is_tty = true;
  processes.redis.exec = "docker compose up redis";

  # https://devenv.sh/services/
  # https://devenv.sh/reference/options/#services
  # Services are conditionally enabled - disabled when building containers
  services = lib.mkIf (config.devenv.profile != "ci") {
    postgres = {
      enable = !config.container.isBuilding;
      package = pkgs.postgresql_17;
      extensions = exts: [ ];
      initdbArgs = lib.mkIf (!config.container.isBuilding) [
        "-c"
        "config_file=${config.git.root}/infra/postgres/postgresql.conf"
      ];
      initialDatabases = lib.mkIf (!config.container.isBuilding) [
        {
          name = "app";
          pass = "password";
          user = "pguser";
        }
      ];
    };
    # redis = {
    #   enable = !config.container.isBuilding;
    # };
  };

  # https://devenv.sh/scripts/
  # https://devenv.sh/reference/options/#scripts
  scripts.enable-cache-push.exec = ''
    # echo '{ cachix.push = "acme"; }' > devenv.local.nix
    export CACHIX_AUTH_TOKEN=$(chamber read dev/common cachix-auth-token -q)
  '';
  scripts.refresh-aws.exec = ''
    aws sso login --profile acme-dev
  '';
  scripts.load-env.exec = ''
    ENV="''${ENV:-dev/apollo}"
    source <(chamber env $ENV)
  '';
  scripts.turbo-auth.exec = ''
    export TURBO_TOKEN=$(${pkgs.chamber}/bin/chamber read dev/common turbo-token -q)
  '';
  scripts.db-migrate.exec = ''
    ${pkgs.turbo}/bin/turbo -F @acme/db migrate
  '';
  scripts.start.exec = ''
    tasks=("lint" "format" "test")
    apps=("apollo" "nn" "turbo")
    selected_task=$(${pkgs.gum}/bin/gum choose --header "Select a task to run:" ''${tasks[@]})
    selected_app=$(${pkgs.gum}/bin/gum choose --header "Select an app to run the task on:" ''${apps[@]} "all")
    if [ "$selected_app" == "all" ]; then
      for app in ''${apps[@]}; do
        devenv tasks run $app:$selected_task
      done
    else
      devenv tasks run $selected_app:$selected_task
    fi
  '';

  # https://devenv.sh/basics/
  # https://devenv.sh/reference/options/#entershell
  enterShell = ''
    if [ -z "$GITHUB_ACTIONS" ]; then
      export XDG_CONFIG_HOME="''${HOME}/.config"
      mkdir -p "$XDG_CONFIG_HOME/process-compose"
      # Initialize Starship prompt
      eval "$(${pkgs.starship}/bin/starship init $SHELL)"

      # Show MOTD
      source $DEVENV_ROOT/scripts/activate.sh


      # Remove this path from PATH to avoid infinite recursion
      stripped=$(sed 's/:node_modules\/.bin//g' <<< "$PATH")
      export PATH="$stripped:node_modules/.bin"
    fi
  '';

  # https://devenv.sh/tasks/
  # https://devenv.sh/reference/options/#tasks
  # Auto-auth for remote cache even without a Vercel account
  tasks."util:turbo-auth" = {
    cwd = "${config.git.root}";
    exec = ''
      export TURBO_TOKEN=$(${pkgs.chamber}/bin/chamber read apollo-workspace turbo-token -q)
    '';
  };
  # "devenv:enterShell".after = [ "util:turbo-auth" ];
  tasks."turbo:build" = {
    cwd = "${config.git.root}";
    description = "Build all projects using Turbo";
    exec = ''
      ${pkgs.turbo}/bin/turbo build
    '';
  };
  tasks."turbo:lint" = {
    cwd = "${config.git.root}";
    description = "Lint all projects using Turbo";
    exec = ''
      ${pkgs.turbo}/bin/turbo lint
    '';
  };
  tasks."turbo:test" = {
    cwd = "${config.git.root}";
    description = "Run all tests using Turbo";
    exec = ''
      ${pkgs.turbo}/bin/turbo test
    '';
  };
  tasks."turbo:checks:ci" = {
    cwd = "${config.git.root}";
    description = "CI linting and typechecking for Turbo workspaces";
    exec = ''
      set -euo pipefail
      ${pkgs.pnpm}/bin/pnpm lint --affected
      ${pkgs.pnpm}/bin/pnpm check
      ${pkgs.pnpm}/bin/pnpm typecheck
    '';
  };
  tasks."tests:turbo:ci" = {
    cwd = "${config.git.root}";
    description = "Run Turbo-powered tests (CI-friendly coverage outputs)";
    exec = ''
      set -euo pipefail
      test_exit=0
      if ! ${pkgs.pnpm}/bin/pnpm env:workspace turbo run test; then
        test_exit=$?
      fi
      ${pkgs.pnpm}/bin/pnpm env:workspace turbo run report --filter=@acme/vitest-config
      exit $test_exit
    '';
  };
  tasks."turbo:format" = {
    cwd = "${config.git.root}";
    description = "Format all code using Turbo";
    exec = ''
      ${pkgs.turbo}/bin/turbo format
    '';
  };
  tasks."turbo:check" = {
    cwd = "${config.git.root}";
    description = "Run all checks using Turbo";
    exec = ''
      ${pkgs.turbo}/bin/turbo check
    '';
  };
  tasks."pnpm:install" = {
    cwd = "${config.git.root}";
    description = "Install all dependencies using pnpm";
    exec = ''
      ${pkgs.pnpm}/bin/pnpm install
    '';
  };
  tasks."coverage:generate" = {
    cwd = "${config.git.root}";
    description = "Generate coverage report using pnpm";
    exec = ''
      ${pkgs.pnpm}/bin/pnpm report
    '';
  };
  tasks."treefmt:full" = {
    cwd = config.git.root;
    description = "Full treefmt run with no caching";
    exec = ''
      ${pkgs.treefmt}/bin/treefmt \
        --verbose \
        --clear-cache --no-cache \
        --working-dir $DEVENV_ROOT \
        --walk git
    '';
  };

  # https://devenv.sh/tests/
  # https://devenv.sh/reference/options/#entertest
  enterTest = ''
    echo "Running tests"
    ${pkgs.pnpm}/bin/pnpm test
  '';

  # https://devenv.sh/pre-commit-hooks/
  # https://devenv.sh/reference/options/#pre-commit
  git-hooks.hooks.shellcheck.enable = true;
  # git-hooks.hooks.biome.enable = true;
  # Use the Biome package directly instead of referencing an undefined treefmt option
  git-hooks.hooks.biome.settings.binPath = "${
    config.treefmt.config.programs.biome.package or pkgs.biome
  }/bin/biome";

  # https://devenv.sh/reference/options/#treefmt
  # Treefmt configuration - uses devenv built-in formatter support
  # Formatters automatically respect existing project configs (biome.json, ruff.toml, etc.)
  # config.programs automatically populates config.settings.formatter
  treefmt = {
    enable = true;
    # Explicitly set projectRootFile to ensure wrapper finds project root correctly
    # Use a repository-relative marker so CI runners don't try to walk to /
    config.projectRootFile = "pnpm-workspace.yaml";
    config.programs = {
      # Nix formatter
      alejandra.enable = true;
      # Protobuf
      buf.enable = true;
      # buf.settings = lib.mkDefault (import ./apps/apollo/api/proto/buf.yaml); # This line caused a syntax error because Nix cannot directly import YAML.
      # If buf needs a config file, you might need to use builtins.readFile or a specific 'configFile' option in a buf module.
      # Go formatters
      gofmt.enable = true;
      goimports.enable = true;
      golines.enable = true;
      # golangci-lint doesn't work well with treefmt (needs package patterns, not individual files)
      # Run separately: cd apps/apollo && golangci-lint run --fix --config .golangci.yml ./...
      # golangci-lint.enable = true;
      # golangci-lint.configFile = lib.mkDefault "${config.git.root}/apps/apollo/.golangci.yml";
      # Python formatter - respects apps/nn/ruff.toml automatically
      ruff-check.enable = true;
      ruff-format.enable = true;
      ruff-format.lineLength = 88;
      # JavaScript/TypeScript formatter - respects biome.json automatically
      biome.enable = true;
      biome.package = pkgs.biome;
      biome.settings = import ./tooling/nix/biome.nix { inherit pkgs lib; };
      biome.validate.enable = false;
      biome.validate.schema = false;
      # With empty settings, Biome will auto-discover biome.json in the project
      # Markdown formatter - no project config, use built-in
      mdformat.enable = true;
      # YAML formatter - no project config, use built-in
      yamlfmt.enable = true;
    };
    config.settings.global.excludes = [
      "**/node_modules/**"
      "**/.venv/**"
      "**/.git/**"
      "**/dist/**"
      "**/build/**"
      "**/.next/**"
      "**/.turbo/**"
      "**/coverage/**"
      "**/.pytest_cache/**"
      "**/__pycache__/**"
      "**/.mypy_cache/**"
      "**/result/**"
      "**/.direnv/**"
      "**/.devenv/**"
      "**/.devenv*/**"
      "**/.yarn/releases/**"
      "**/static/**"
      "tooling/typescript/base.json"
      "/Applications/**"
      "/System/**"
      "/usr/**"
      "/opt/**"
      "/Library/**"
      "/private/**"
    ];
    # Global settings - excludes and other global options
    # These excludes prevent treefmt from formatting files outside the project
    # If a configured path doesnt match any formatters, log at this level
    config.settings.global.on-unmatched = "info";
  };

  # https://devenv.sh/guides/using-with-cachix/
  # Binary caching with Cachix
  # Disable automatic cache management to avoid requiring trusted-users on the daemon.
  cachix.enable = true;
  # If you want to push/pull via Cachix, enable it locally or configure system-level substituters.
  cachix.pull = [
    "devenv"
    "acme"
  ];
  cachix.push = "acme";

  # https://devenv.sh/process-managers/process-compose/
  process.managers = {
    process-compose = {
      tui.enable = true;
      settings = {
        environment = [
          "TURBO_UI=false"
        ];
      };
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
