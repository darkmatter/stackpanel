# ==============================================================================
# commands.nix
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  # Get user-defined apps (before computed values)
  rawCommands = config.stackpanel.commands;
  db = import ../../db { inherit lib; };

  # Nix-specific app options (not in proto schema)
  # These are runtime/devenv options that don't belong in serialized data
  nixCommandOptionsModule =
    { lib, ... }:
    {
      options = {
        configPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Repo-relative config file path for the tool.";
        };
        configArg = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "Argument prefix inserted before configPath (e.g. [\"--config\"]).";
        };
      };
    };
  commandNames = lib.attrNames rawCommands;
  computedCommands = lib.listToAttrs (
    lib.imap0 (
      idx: name:
      let
        cmd = rawCommands.${name};
      in
      {
        name = name;
        cmd = cmd;
      }
    ) commandNames
  );
in
{
  options.stackpanel.commandModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Additional modules to extend command configuration options.
    '';
  };
  options.stackpanel.commands = lib.mkOption {
    # type = lib.types.attrsOf appType;
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [
          # Proto-derived options (name, path, install-command, etc.)
          { options = db.extend.command; }
          # Nix-specific runtime options (tooling, offset, domain, tls)
          nixCommandOptionsModule
        ]
        ++ config.stackpanel.commandModules;
        specialArgs = { inherit lib; };
      }
    );
    default = { };
    description = ''
      # Stackpanel commands

    '';
    example = lib.literalExpression ''
      {
        "db:seed": {
          package = "npm";
          command = "run seed";
          domain = "localhost";
          env = {
            NODE_ENV = "development";
          };
          cwd = null;
        }
      }
    '';
  };

  # Expose computed app info for programmatic access
  options.stackpanel.commandsComputed = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
    readOnly = true;
    default = computedCommands;
    description = "Computed app configurations with ports and URLs";
  };
}
