# ==============================================================================
# compat.nix
#
# Host options for the copied devenv language modules. Those files still
# assign `packages`, `env`, `enterShell`, and the other devenv outputs.
# This module declares that surface and forwards the shell effects onto
# stackpanel.devshell.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  inputs ? { },
  ...
}:
let
  dirs = config.stackpanel.dirs;
  # Shell snippets run with cwd at the working tree. stackpanel.root is the
  # flake's store snapshot, so state stays relative to that cwd.
  root = ".";
  profileReady =
    config.stackpanel.enable
    && config.stackpanel.devshell.profile.enable
    && config.stackpanel.devshell.packages != [ ];

  stringEnv = lib.concatMapAttrs (
    name: value:
    if value == null then
      { }
    else if builtins.isBool value then
      {
        ${name} = if value then "1" else "0";
      }
    else if
      builtins.isString value || builtins.isPath value || builtins.isInt value || lib.isDerivation value
    then
      {
        ${name} = toString value;
      }
    else
      throw "devenv language env.${name} cannot be exported (${builtins.typeOf value})"
  ) config.env;

  taskHooks = lib.concatLists (
    lib.mapAttrsToList (
      _: task:
      if builtins.isAttrs task && task ? exec && builtins.isString task.exec then [ task.exec ] else [ ]
    ) config.tasks
  );

  failedAssertions = builtins.filter (x: !x.assertion) config.assertions;

  serviceEnable = name: (config.stackpanel.services.${name} or { enable = false; }).enable or false;
in
{
  options.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    internal = true;
    description = "Packages contributed by copied devenv language modules.";
  };

  options.env = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
    default = { };
    internal = true;
    description = "Environment values contributed by copied devenv language modules.";
  };

  options.enterShell = lib.mkOption {
    type = lib.types.lines;
    default = "";
    internal = true;
    description = "Shell snippet contributed by copied devenv language modules.";
  };

  options.changelogs = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = [ ];
    internal = true;
    description = "Changelog entries recorded by copied devenv language modules.";
  };

  options.git-hooks = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    internal = true;
    description = "git-hooks.nix fragment set by copied devenv language modules.";
  };

  options.files = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        freeformType = lib.types.attrsOf lib.types.raw;
      }
    );
    default = { };
    internal = true;
    description = "Files written by copied devenv language modules.";
  };

  options.tasks = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    internal = true;
    description = "One-shot setup tasks from copied devenv language modules.";
  };

  options.assertions = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    default = [ ];
    internal = true;
    description = "Assertions from copied devenv language modules.";
  };

  options.warnings = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    internal = true;
    description = "Warnings from copied devenv language modules.";
  };

  options.processes = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    internal = true;
    description = "Process entries from copied devenv language modules.";
  };

  options.cachix = {
    enable = lib.mkEnableOption "Cachix" // {
      default = false;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cachix;
      description = "Cachix package, read by the copied Nix language module.";
    };
    pull = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Cache names requested by copied language modules.";
    };
  };

  options.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    internal = true;
    description = "Helpers the copied devenv language modules call.";
  };

  options.devenv = {
    root = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "Project root, as copied devenv language modules see it.";
    };
    state = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "Persistent language state directory.";
    };
    dotfile = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "Stackpanel home directory used where devenv used its dotfile.";
    };
    profile = lib.mkOption {
      type = lib.types.either lib.types.str lib.types.package;
      internal = true;
      description = "Devshell profile path used by copied language modules.";
    };
  };

  options.services = {
    redis.enable = lib.mkEnableOption "redis" // {
      default = false;
    };
    mysql.enable = lib.mkEnableOption "mysql" // {
      default = false;
    };
    rabbitmq.enable = lib.mkEnableOption "rabbitmq" // {
      default = false;
    };
    blackfire = {
      enable = lib.mkEnableOption "blackfire" // {
        default = false;
      };
      socket = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Blackfire agent socket.";
      };
    };
    tideways.enable = lib.mkEnableOption "tideways" // {
      default = false;
    };
  };

  config = {
    lib = {
      mkOverrideDefault = lib.mkOverride 500;
      _fileChecksum =
        path:
        "$(${pkgs.coreutils}/bin/cksum ${lib.escapeShellArg path} | ${pkgs.coreutils}/bin/cut -f1 -d' ')";
      getInput =
        args:
        inputs.${args.name} or (throw ''
          ${args.attribute} needs the `${args.name}` flake input.
          Add it to the flake that evaluates stackpanel:

            inputs.${args.name}.url = "${args.url}";
            ${lib.concatMapStrings (follow: ''
              inputs.${args.name}.inputs.${follow}.follows = "${follow}";
            '') (args.follows or [ ])}'');
    };

    devenv = {
      root = root;
      state = dirs.profile;
      dotfile = dirs.home;
      profile = if profileReady then config.stackpanel.devshell.profile.package else dirs.profile;
    };

    env = {
      DEVENV_ROOT = root;
      DEVENV_STATE = dirs.profile;
      DEVENV_RUNTIME = "${dirs.profile}/run";
    }
    // lib.optionalAttrs profileReady {
      DEVENV_PROFILE = config.stackpanel.devshell.profile.package;
    };

    services.redis.enable = lib.mkDefault (serviceEnable "redis");
    services.mysql.enable = lib.mkDefault (serviceEnable "mysql");
    services.rabbitmq.enable = lib.mkDefault (serviceEnable "rabbitmq");

    stackpanel.devshell.packages =
      lib.warnIf (config.warnings != [ ]) (lib.concatStringsSep "\n" config.warnings)
        (
          if failedAssertions != [ ] then
            throw (lib.concatMapStringsSep "\n" (x: x.message) failedAssertions)
          else
            config.packages
        );
    stackpanel.devshell.env = stringEnv;
    stackpanel.devshell.hooks.main =
      taskHooks ++ lib.optional (config.enterShell != "") config.enterShell;
    stackpanel.git-hooks = lib.mkIf (config.git-hooks != { }) config.git-hooks;
  };
}
