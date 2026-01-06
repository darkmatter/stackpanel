# ==============================================================================
# stackpanel.nix
#
# Stackpanel-specific options for the stackpanel repository itself.
# This file contains configuration for multiple systems, each under their own key:
#   - stackpanel: Stackpanel module options
#   - devenv: Devenv-specific options (packages, languages, env, etc.)
#   - git-hooks: Git hooks configuration
#
# Imported by devshell.nix which extracts each section appropriately.
# ==============================================================================
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  # ---------------------------------------------------------------------------
  # Auto-import data "tables" from ./data/
  # Each .nix file becomes a top-level key under stackpanel.*
  # ---------------------------------------------------------------------------
  dataDir = ./data;

  loadDataTables =
    dir:
    let
      entries = builtins.readDir dir;
      nixFiles = lib.filterAttrs (
        n: type: type == "regular" && lib.hasSuffix ".nix" n && n != "default.nix" && (!lib.hasPrefix "_" n)
      ) entries;
      toKey = n: lib.removeSuffix ".nix" n;
    in
    lib.mapAttrs' (n: _: {
      name = toKey n;
      value = import (dir + "/${n}");
    }) nixFiles;

  # Load all data tables
  data = if builtins.pathExists dataDir then loadDataTables dataDir else { };

  ghCollabs = import ./external/github-collaborators.nix;

  # Transform a GitHub collaborator to stackpanel user format
  toUser = name: collab: {
    inherit name;
    github = collab.login;
    public-keys = collab.publicKeys;
    # Default environments based on admin status
    secrets-allowed-environments =
      if collab.isAdmin then
        [
          "dev"
          "staging"
          "production"
        ]
      else
        [ "dev" ];
  };
  # ghusers = ghCollabs.collaborators;
  github-team = lib.mapAttrs (name: user: toUser name user) ghCollabs.collaborators;
  # github-data-by-username = {
  #   is-admin = lib.mapAttrs (name: user: user.isAdmin) ghusers;
  #   public-keys = lib.mapAttrs (name: user: user.publicKeys) ghusers;
  # };
in
{
  # ===========================================================================
  # Stackpanel options
  # ===========================================================================
  stackpanel = lib.recursiveUpdate {
    enable = true;
    name = "stackpanel";
    github = "darkmatter/stackpanel";
    debug = true;
    theme.enable = true;
    ide.enable = true;
    cli.enable = true;

    # Packages for the devshell
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

    # AWS Roles Anywhere via stackpanel's AWS module
    aws.roles-anywhere = {
      enable = true;
      region = "us-west-2";
      account-id = "950224716579";
      role-name = "darkmatter-dev";
      trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:trust-anchor/c99a9383-6be1-48ba-8e63-c3ab6b7069cb";
      profile-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:profile/4e72b392-9074-4e53-8cd0-1ba50856d1ca";
    };

    # Step CA
    step-ca = {
      enable = true;
      ca-url = "https://ca.internal:443";
      ca-fingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
      provisioner = "Authentik";
      prompt-on-shell = true;
      cert-name = "device";
    };

    # MOTD content
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
    devshell.hooks.main = [
      ''
        echo "✅ Stackpanel development environment"
      ''
    ];

    git-hooks = {
      enable = true;
    };

    # ============================================================================
    # Apps - web app, docs, and Go CLI/agent
    # ============================================================================
    apps.web = {
      name = "web";
      domain = "stackpanel";
      tls = true;
    };
    apps.server = {
      name = "server";
    };
    apps.docs = {
      name = "docs";
      domain = "docs";
    };
    # Unified CLI + Agent app
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
        generateFiles = false; # Already has package.json, .air.toml, tools.go
      };
    };

    # ============================================================================
    # Ports - infrastructure service ports
    # ============================================================================
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

    # ============================================================================
    # Global Services - PostgreSQL, Redis, Minio, Caddy
    # ============================================================================
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

    # ============================================================================
    # Users
    # ============================================================================
    users = lib.recursiveUpdate github-team {
      cooper = {
        name = "Cooper Maruyama";
        github = "coopmoney";
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

    secrets = {
      input-directory = "infra/secrets";
      # enable = true;
      environments = {
        "web/dev" = {
          name = "dev";
          sources = [
            "shared"
            "dev"
          ];
          public-keys = [ "age1..." ];
        };
        "web/staging" = {
          name = "staging";
          sources = [
            "shared"
            "staging"
          ];
          public-keys = [ "age1..." ];
        };
        "web/production" = {
          name = "production";
          sources = [
            "shared"
            "production"
          ];
          public-keys = [ "age1..." ];
        };
      };
    };

    ide.vscode = {
      enable = true;
      extensions = [
        "ms-azuretools.vscode-docker"
        "golang.go"
      ];
      extra-folders = [ ];
    };
  } data;
}
