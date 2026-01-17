# ==============================================================================
# _internal.nix
#
# INTERNAL ENTRY POINT - DO NOT EDIT
#
# This file imports config.nix (user-editable) and handles:
#   - Auto-loading data tables from ./data/
#   - Merging GitHub collaborators
#   - Combining everything into the final stackpanel config
#
# Usage in templates:
#   stackpanel = import ./.stackpanel/_internal.nix { inherit pkgs lib; };
#
# Users should edit config.nix instead.
# ==============================================================================
{ pkgs, lib }:
let
  # ---------------------------------------------------------------------------
  # Import user config
  # Handles both plain attrset and function ({ pkgs }: ...) formats
  # ---------------------------------------------------------------------------
  rawConfig = import ./config.nix;
  userConfig = if builtins.isFunction rawConfig then rawConfig { inherit pkgs; } else rawConfig;

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
  # Start with user config, merge in GitHub team users, then merge data tables
  configWithUsers = userConfig // {
    users = lib.recursiveUpdate github-team (userConfig.users or { });
  };

in
# Return the merged config directly
lib.recursiveUpdate configWithUsers data
