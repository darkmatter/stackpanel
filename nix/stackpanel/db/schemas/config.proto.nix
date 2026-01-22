# ==============================================================================
# config.proto.nix
#
# Protobuf schema for Stackpanel project configuration.
# This is the root configuration file at .stackpanel/config.nix
# ==============================================================================
{lib}: let
  proto = import ../lib/proto.nix {inherit lib;};
in
  proto.mkProtoFile {
    name = "config.proto";
    package = "stackpanel.db";

    # User-editable config file boilerplate - clean and simple (plain attrset)
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

        # -------------------------------------------------------------------------
        # Users
        # GitHub team members are auto-imported via _internal.nix.
        # Add overrides or additional users here.
        # -------------------------------------------------------------------------
        # users = {
        #   example = {
        #     name = "Example User";
        #     github = "example";
        #     email = "example@example.com";
        #   };
        # };
      }
    '';

    # Internal entry point that imports config.nix and handles merging
    # Returns the merged config attrset directly (not wrapped in { stackpanel = ... })
    internalBoilerplate = ''
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
            value = import (dir + "/''${n}");
          }) nixFiles;

        # Load all data tables
        data = if builtins.pathExists dataDir then loadDataTables dataDir else { };

        # ---------------------------------------------------------------------------
        # GitHub collaborators transformation
        # ---------------------------------------------------------------------------
        ghCollabsPath = ./external/github-collaborators.nix;
        ghCollabs = if builtins.pathExists ghCollabsPath
          then import ghCollabsPath
          else { collaborators = { }; };

        # Transform a GitHub collaborator to stackpanel user format
        toUser = name: collab: {
          inherit name;
          github = collab.login or name;
          email = collab.email or null;
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
