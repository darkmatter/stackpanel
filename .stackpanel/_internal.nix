# ==============================================================================
# _internal.nix
#
# INTERNAL ENTRY POINT - DO NOT EDIT
#
# This file imports config.nix (user-editable) and handles:
#   - Processing `imports` directive for config data
#   - Auto-loading data tables from ./data/
#   - Merging GitHub collaborators
#   - Loading config.local.nix for per-user overrides (gitignored)
#   - Applying STACKPANEL_CONFIG_OVERRIDE env var (JSON, for rare CI/scripting cases)
#   - Combining everything into the final stackpanel config
#
# Merge priority (lowest to highest):
#   1. Data tables (./data/*.nix)
#   2. User config (config.nix)
#   3. Local overrides (config.local.nix - gitignored, preferred for local dev)
#   4. STACKPANEL_CONFIG_OVERRIDE (JSON env var - for CI/scripting, warns on use)
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
  # ---------------------------------------------------------------------------
  rawConfig = import ./config.nix;
  baseUserConfig = if builtins.isFunction rawConfig then rawConfig { inherit pkgs; } else rawConfig;

  # ---------------------------------------------------------------------------
  # Import local config overrides (per-user, gitignored)
  # ---------------------------------------------------------------------------
  localConfigPath = ./config.local.nix;
  hasLocalConfig = builtins.pathExists localConfigPath;
  rawLocalConfig = if hasLocalConfig then import localConfigPath else {};
  localConfig = if builtins.isFunction rawLocalConfig then rawLocalConfig { inherit pkgs lib; } else rawLocalConfig;

  # ---------------------------------------------------------------------------
  # Process imports directive in config.nix
  # For simple config imports (plain attrsets, not full modules)
  # ---------------------------------------------------------------------------
  processImports = config:
    let
      imports = config.imports or [];
      configWithoutImports = builtins.removeAttrs config [ "imports" ];

      # Import each module, handling both attrset and function forms
      importModule = path:
        let
          imported = import path;
          result = if builtins.isFunction imported then imported { inherit pkgs lib; } else imported;
        in
        # Recursively process imports in the imported module
        processImports result;

      # Merge all imported configs with the base config
      importedConfigs = map importModule imports;
    in
    lib.foldl lib.recursiveUpdate {} (importedConfigs ++ [ configWithoutImports ]);

  # Process imports in the user config
  userConfig = processImports baseUserConfig;

  # ---------------------------------------------------------------------------
  # Auto-import data "tables" from ./data/
  # Each .nix file becomes a top-level key under stackpanel.*
  # ---------------------------------------------------------------------------
  dataDir = ./data;

  # Files that are data-only (read by agent) and don't have corresponding module options
  # These should NOT be merged into stackpanel.* config
  dataOnlyFiles = [
    "variables.nix"
    "commands.nix"
    "apps.nix"
    "tasks.nix"
    "packages.nix" # Contains strings, resolved by user-packages.nix
  ];

  loadDataTables =
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
      value = import (dir + "/${n}");
    }) nixFiles;

  # Load all data tables
  data = if builtins.pathExists dataDir then loadDataTables dataDir else { };

  # ---------------------------------------------------------------------------
  # GitHub collaborators transformation
  # ---------------------------------------------------------------------------
  ghCollabsPath = ./external/github-collaborators.nix;
  ghCollabs =
    if builtins.pathExists ghCollabsPath then import ghCollabsPath else { collaborators = { }; };

  # Transform a GitHub collaborator to stackpanel user format
  toUser = name: collab: {
    inherit name;
    github = collab.login or name;
    public-keys = collab.publicKeys or [ ];
    # Default environments based on admin status
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
  # Merge user config with auto-loaded data
  # ---------------------------------------------------------------------------
  # Data tables provide defaults, user config (config.nix) takes precedence
  configWithUsers = userConfig // {
    users = lib.recursiveUpdate github-team (userConfig.users or { });
  };

  # ---------------------------------------------------------------------------
  # Environment variable override (JSON)
  # For rare CI/scripting cases where config.local.nix isn't practical.
  # Logs a warning when used to encourage using config.local.nix instead.
  # ---------------------------------------------------------------------------
  envOverrideRaw = builtins.getEnv "STACKPANEL_CONFIG_OVERRIDE";
  hasEnvOverride = envOverrideRaw != "";
  envOverride = 
    if hasEnvOverride then
      builtins.fromJSON envOverrideRaw
    else
      {};

  # ---------------------------------------------------------------------------
  # Final merge order:
  #   1. Data tables (defaults)
  #   2. User config (config.nix)
  #   3. Local overrides (config.local.nix - gitignored)
  #   4. STACKPANEL_CONFIG_OVERRIDE (JSON env var - highest priority)
  # ---------------------------------------------------------------------------
  baseConfig = lib.recursiveUpdate data configWithUsers;
  configWithLocal = lib.recursiveUpdate baseConfig localConfig;
  finalConfig = lib.recursiveUpdate configWithLocal envOverride;

  # Add metadata about overrides for debugging
  configMeta = {
    _meta = {
      hasLocalConfig = hasLocalConfig;
      hasEnvOverride = hasEnvOverride;
    };
  };

in
# Return final config (optionally with metadata for debugging)
# Note: STACKPANEL_CONFIG_OVERRIDE usage will log a warning in shell hooks
finalConfig
