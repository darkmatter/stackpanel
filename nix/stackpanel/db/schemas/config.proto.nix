# ==============================================================================
# config.proto.nix
#
# Protobuf schema for Stackpanel project configuration.
# This is the root configuration file at .stackpanel/config.nix
#
# This file also contains boilerplate templates for scaffolding new projects.
# The `stackpanel scaffold` command and `nix flake init` templates use these.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "config.proto";
  package = "stackpanel.db";

  # ==========================================================================
  # User-editable config.nix boilerplate
  # This is the main configuration file users edit
  # ==========================================================================
  boilerplate = ''
    # ==============================================================================
    # config.nix
    #
    # Stackpanel project configuration.
    # Edit this file to configure your project.
    # ==============================================================================
    {
      enable = true;
      name = "my-project";
      github = "owner/repo";
      # debug = false;

      # ---------------------------------------------------------------------------
      # CLI - Stackpanel command-line tools
      # ---------------------------------------------------------------------------
      cli.enable = true;

      # ---------------------------------------------------------------------------
      # Theme - Starship prompt with stackpanel styling
      # See: https://stackpanel.dev/docs/theme
      # ---------------------------------------------------------------------------
      theme.enable = true;
      # theme = {
      #   name = "default";
      #   nerd-font = true;
      #   minimal = false;
      #
      #   colors = {
      #     primary = "#7aa2f7";
      #     secondary = "#bb9af7";
      #     success = "#9ece6a";
      #     warning = "#e0af68";
      #     error = "#f7768e";
      #     muted = "#565f89";
      #   };
      #
      #   starship = {
      #     add-newline = true;
      #     scan-timeout = 30;
      #     command-timeout = 500;
      #   };
      # };

      # ---------------------------------------------------------------------------
      # IDE Integration - Auto-generate editor config files
      # ---------------------------------------------------------------------------
      ide.enable = true;
      ide.vscode.enable = true;

      # ---------------------------------------------------------------------------
      # MOTD - Message of the day shown on shell entry
      # ---------------------------------------------------------------------------
      motd.enable = true;
      motd.commands = [
        {
          name = "dev";
          description = "Start development server";
        }
        {
          name = "build";
          description = "Build the project";
        }
      ];

      # ---------------------------------------------------------------------------
      # Users - Team members with project access
      # GitHub team members are auto-imported via _internal.nix.
      # Add overrides or additional users here.
      # See: https://stackpanel.dev/docs/users
      # ---------------------------------------------------------------------------
      # users = {
      #   johndoe = {
      #     name = "John Doe";
      #     github = "johndoe";
      #     email = "john@example.com";
      #   };
      # };

      # ---------------------------------------------------------------------------
      # AWS - AWS Roles Anywhere for certificate-based authentication
      # See: https://stackpanel.dev/docs/aws
      # ---------------------------------------------------------------------------
      # aws = {
      #   roles-anywhere = {
      #     enable = true;
      #     region = "us-east-1";
      #     account-id = "123456789012";
      #     role-name = "DeveloperRole";
      #     trust-anchor-arn = "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/...";
      #     profile-arn = "arn:aws:rolesanywhere:us-east-1:123456789012:profile/...";
      #     cache-buffer-seconds = "300";
      #     prompt-on-shell = true;
      #   };
      # };

      # ---------------------------------------------------------------------------
      # Step CA - Internal certificate management for local HTTPS
      # See: https://stackpanel.dev/docs/step-ca
      # ---------------------------------------------------------------------------
      # step-ca = {
      #   enable = true;
      #   ca-url = "https://ca.internal:443";
      #   ca-fingerprint = "abc123...";  # Root CA fingerprint for verification
      #   provisioner = "admin";
      #   cert-name = "dev-workstation";
      #   prompt-on-shell = true;
      # };

      # ---------------------------------------------------------------------------
      # Secrets - Secrets management configuration
      # See: https://stackpanel.dev/docs/secrets
      # ---------------------------------------------------------------------------
      # secrets = {
      #   enable = true;
      #   input-directory = ".stackpanel/secrets";
      #
      #   # Code generation for type-safe env access
      #   codegen = {
      #     typescript = {
      #       name = "env";
      #       directory = "packages/env/src/generated";
      #       language = "typescript";
      #     };
      #   };
      # };

      # ---------------------------------------------------------------------------
      # SST - Infrastructure as code configuration
      # See: https://stackpanel.dev/docs/sst
      # ---------------------------------------------------------------------------
      # sst = {
      #   enable = true;
      #   project-name = "my-project";
      #   region = "us-west-2";
      #   account-id = "123456789012";
      #   config-path = "packages/infra/sst.config.ts";
      #
      #   kms = {
      #     enable = true;
      #     alias = "my-project-secrets";
      #   };
      #
      #   oidc = {
      #     provider = "github-actions";
      #     github-actions = {
      #       org = "my-org";
      #       repo = "*";
      #     };
      #   };
      # };

      # ---------------------------------------------------------------------------
      # Global Services - Shared development services
      # ---------------------------------------------------------------------------
      # globalServices = {
      #   enable = true;
      #   project-name = "myproject";
      #   postgres.enable = true;
      #   redis.enable = true;
      #   minio.enable = true;
      # };

      # ---------------------------------------------------------------------------
      # Caddy - Local HTTPS reverse proxy
      # ---------------------------------------------------------------------------
      # caddy = {
      #   enable = true;
      #   project-name = "myproject";
      # };
    }
  '';

  # ==========================================================================
  # Internal entry point (_internal.nix) boilerplate
  # This handles merging config.nix with data files and GitHub collaborators
  # ==========================================================================
  internalBoilerplate = ''
    # ==============================================================================
    # _internal.nix
    #
    # INTERNAL ENTRY POINT - DO NOT EDIT
    #
    # This file imports config.nix (user-editable) and handles:
    #   - Processing `imports` directive for config data
    #   - Auto-loading data from ./data.nix (consolidated) or ./data/ (legacy)
    #   - Merging GitHub collaborators
    #   - Loading config.local.nix for per-user overrides (gitignored)
    #   - Applying STACKPANEL_CONFIG_OVERRIDE env var (JSON, for CI/scripting)
    #   - Combining everything into the final stackpanel config
    #
    # Merge priority (lowest to highest):
    #   1. Data tables (data.nix or data/*.nix)
    #   2. User config (config.nix)
    #   3. Local overrides (config.local.nix - gitignored)
    #   4. STACKPANEL_CONFIG_OVERRIDE (JSON env var)
    #
    # Usage:
    #   stackpanel = import ./.stackpanel/_internal.nix { inherit pkgs lib; };
    #
    # Users should edit config.nix instead.
    # For local overrides, use config.local.nix (gitignored).
    # ==============================================================================
    { pkgs, lib }:
    let
      # ---------------------------------------------------------------------------
      # Import user config
      # Handles both plain attrset and function ({ pkgs }: ...) formats
      # ---------------------------------------------------------------------------
      rawConfig = import ./config.nix;
      baseUserConfig = if builtins.isFunction rawConfig then rawConfig { inherit pkgs; } else rawConfig;

      # ---------------------------------------------------------------------------
      # Import local config overrides (per-user, gitignored)
      # Uses absolute path to bypass flake's gitignore filtering
      # ---------------------------------------------------------------------------
      stackpanelRoot =
        let
          envRoot = builtins.getEnv "STACKPANEL_ROOT";
          markerRoot =
            let
              markerPath = ../.stackpanel-root;
            in
            if builtins.pathExists markerPath then
              lib.removeSuffix "\n" (builtins.readFile markerPath)
            else
              null;
        in
        if envRoot != "" then
          envRoot
        else if markerRoot != null && markerRoot != "." then
          markerRoot
        else
          null;

      localConfigPath =
        if stackpanelRoot != null then stackpanelRoot + "/.stackpanel/config.local.nix" else null;
      hasLocalConfig = localConfigPath != null && builtins.pathExists localConfigPath;
      rawLocalConfig = if hasLocalConfig then import localConfigPath else { };
      localConfig =
        if builtins.isFunction rawLocalConfig then rawLocalConfig { inherit pkgs lib; } else rawLocalConfig;

      # ---------------------------------------------------------------------------
      # Process imports directive in config.nix
      # ---------------------------------------------------------------------------
      processImports =
        config:
        let
          imports = config.imports or [ ];
          configWithoutImports = builtins.removeAttrs config [ "imports" ];
          importModule =
            path:
            let
              imported = import path;
              result = if builtins.isFunction imported then imported { inherit pkgs lib; } else imported;
            in
            processImports result;
          importedConfigs = map importModule imports;
        in
        lib.foldl lib.recursiveUpdate { } (importedConfigs ++ [ configWithoutImports ]);

      userConfig = processImports baseUserConfig;

      # ---------------------------------------------------------------------------
      # Auto-import data from ./data.nix (consolidated) or ./data/ (legacy)
      # ---------------------------------------------------------------------------
      dataFile = ./data.nix;
      legacyDataDir = ./data;

      dataOnlyFiles = [
        "commands.nix"
        "packages.nix"
      ];

      consolidatedData = if builtins.pathExists dataFile then import dataFile else { };

      loadLegacyDataTables =
        dir:
        let
          entries = builtins.readDir dir;
          nixFiles = lib.filterAttrs (
            n: type:
            type == "regular"
            && lib.hasSuffix ".nix" n
            && n != "default.nix"
            && (!lib.hasPrefix "_" n)
            && (!builtins.elem n dataOnlyFiles)
          ) entries;
          toKey = n: lib.removeSuffix ".nix" n;
        in
        lib.mapAttrs' (n: _: {
          name = toKey n;
          value = import (dir + "/''${n}");
        }) nixFiles;

      legacyData = if builtins.pathExists legacyDataDir then loadLegacyDataTables legacyDataDir else { };
      data = lib.recursiveUpdate legacyData consolidatedData;

      # ---------------------------------------------------------------------------
      # GitHub collaborators transformation
      # ---------------------------------------------------------------------------
      ghCollabsPath = ./external/github-collaborators.nix;
      ghCollabs =
        if builtins.pathExists ghCollabsPath then import ghCollabsPath else { collaborators = { }; };

      toUser = name: collab: {
        inherit name;
        github = collab.login or name;
        public-keys = collab.publicKeys or [ ];
        secrets-allowed-environments =
          if collab.isAdmin or false then
            [ "dev" "staging" "production" ]
          else
            [ "dev" ];
      };

      github-team = lib.mapAttrs (name: user: toUser name user) ghCollabs.collaborators;

      # ---------------------------------------------------------------------------
      # Merge configs
      # ---------------------------------------------------------------------------
      configWithUsers = userConfig // {
        users = lib.recursiveUpdate github-team (userConfig.users or { });
      };

      envOverrideRaw = builtins.getEnv "STACKPANEL_CONFIG_OVERRIDE";
      hasEnvOverride = envOverrideRaw != "";
      envOverride = if hasEnvOverride then builtins.fromJSON envOverrideRaw else { };

      baseConfig = lib.recursiveUpdate data configWithUsers;
      configWithLocal = lib.recursiveUpdate baseConfig localConfig;
      finalConfig = lib.recursiveUpdate configWithLocal envOverride;

    in
    finalConfig
  '';

  # ==========================================================================
  # Consolidated data.nix boilerplate
  # Agent-editable data file (do not edit manually)
  # ==========================================================================
  dataBoilerplate = ''
    # ==============================================================================
    # data.nix - Agent-editable data
    #
    # This file is written by the Stackpanel agent. Do not edit manually.
    # User configuration should go in config.nix instead.
    #
    # The agent patches values at specific paths (e.g., deployment.fly.organization)
    # This file is merged with config.nix by _internal.nix (config.nix takes precedence)
    # ==============================================================================
    { }
  '';

  # ==========================================================================
  # .gitignore boilerplate
  # ==========================================================================
  gitignoreBoilerplate = ''
    # Runtime state (gitignored)
    state/

    # Local config overrides (per-user, gitignored)
    config.local.nix
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    # Root configuration message
    Config = proto.mkMessage {
      name = "Config";
      description = "Stackpanel project configuration";
      fields = {
        enable = proto.bool 1 "Enable stackpanel for this project";
        name = proto.string 2 "Project name";
        github = proto.string 3 "GitHub repository (owner/repo format)";
        debug = proto.bool 4 "Enable debug output";
      };
    };
  };
}
