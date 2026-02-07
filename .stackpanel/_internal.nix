# ==============================================================================
# _internal.nix
#
# INTERNAL ENTRY POINT - DO NOT EDIT
#
# This file imports config.nix (the single source of truth) and handles:
#   - Processing `imports` directive for additional config fragments
#   - Merging GitHub collaborators into users
#   - Loading config.local.nix for per-user overrides (gitignored)
#   - Applying STACKPANEL_CONFIG_OVERRIDE env var (JSON, for CI/scripting)
#
# Merge priority (lowest to highest):
#   1. User config (config.nix)
#   2. Local overrides (config.local.nix - gitignored)
#   3. STACKPANEL_CONFIG_OVERRIDE (JSON env var)
#
# Usage in templates:
#   stackpanel = import ./.stackpanel/_internal.nix { inherit pkgs lib; };
#
# For modules with full NixOS context (config, options, lib.mkIf, etc.),
# use .stackpanel/modules/ - these are imported directly by the devenv adapter.
#
# Users should edit config.nix instead.
# For local overrides, use config.local.nix (gitignored).
# ==============================================================================
{ pkgs, lib }:
let
  # ---------------------------------------------------------------------------
  # Import user config
  # Handles both plain attrset and function ({ pkgs }: ...) formats
  # (function format is for backwards compatibility during Phase 2 AST migration)
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
  # For config fragments (plain attrsets, not full modules)
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
        [
          "dev"
          "staging"
          "production"
        ]
      else
        [ "dev" ];
  };

  github-team = lib.mapAttrs (name: user: toUser name user) ghCollabs.collaborators;

  # ---------------------------------------------------------------------------
  # Merge user config with GitHub collaborators
  # ---------------------------------------------------------------------------
  configWithUsers = userConfig // {
    users = lib.recursiveUpdate github-team (userConfig.users or { });
  };

  # ---------------------------------------------------------------------------
  # Environment variable override (JSON)
  # ---------------------------------------------------------------------------
  envOverrideRaw = builtins.getEnv "STACKPANEL_CONFIG_OVERRIDE";
  hasEnvOverride = envOverrideRaw != "";
  envOverride = if hasEnvOverride then builtins.fromJSON envOverrideRaw else { };

  # ---------------------------------------------------------------------------
  # Final merge order:
  #   1. User config (config.nix)
  #   2. Local overrides (config.local.nix - gitignored)
  #   3. STACKPANEL_CONFIG_OVERRIDE (JSON env var - highest priority)
  # ---------------------------------------------------------------------------
  configWithLocal = lib.recursiveUpdate configWithUsers localConfig;
  finalConfig = lib.recursiveUpdate configWithLocal envOverride;

in
finalConfig
