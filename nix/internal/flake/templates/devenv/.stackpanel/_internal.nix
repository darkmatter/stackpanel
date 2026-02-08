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
      value = import (dir + "/${n}");
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

