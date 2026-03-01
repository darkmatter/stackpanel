# ==============================================================================
# module.nix - Colmena Module Implementation
#
# Provides Colmena deployment tooling with configurable defaults.
#
# This module:
#   1. Defines options under stackpanel.colmena.*
#   2. Adds colmena to devshell packages
#   3. Generates wrapper scripts: colmena-apply, colmena-build, colmena-eval
#   4. Computes resolved flag sets in stackpanel.colmena.computed
#   5. Registers health checks for CLI availability and hive config
#
# Usage:
#   stackpanel.colmena = {
#     enable = true;
#     flake = ".#colmena";
#     parallel = 4;
#     buildOnTarget = true;
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  sp = config.stackpanel;
  cfg = sp.colmena;

  mkFlag = enabled: flag: lib.optionals enabled [ flag ];
  mkValueFlag =
    flag: value:
    lib.optionals (value != null) [
      flag
      (toString value)
    ];
  mkListFlag =
    flag: values:
    lib.optionals (values != [ ]) [
      flag
      (lib.concatStringsSep "," values)
    ];

  commonFlags =
    (lib.optionals (cfg.flake == null) [
      "--config"
      cfg.config
    ])
    ++ mkValueFlag "--flake" cfg.flake
    ++ mkListFlag "--on" cfg.on
    ++ mkListFlag "--exclude" cfg.exclude
    ++ mkFlag cfg.keepResult "--keep-result"
    ++ mkFlag cfg.verbose "--verbose"
    ++ mkFlag cfg.showTrace "--show-trace"
    ++ mkFlag cfg.impure "--impure"
    ++ mkValueFlag "--eval-node-limit" cfg.evalNodeLimit
    ++ mkValueFlag "--parallel" cfg.parallel
    ++ cfg.extraFlags;

  applyFlags =
    commonFlags
    ++ mkFlag cfg.buildOnTarget "--build-on-target"
    ++ mkFlag cfg.uploadKeys "--upload-keys"
    ++ mkFlag cfg.noSubstitute "--no-substitute"
    ++ mkFlag cfg.substituteOnDestination "--substitute-on-destination"
    ++ mkFlag (!cfg.gzip) "--no-gzip"
    ++ mkFlag cfg.reboot "--reboot"
    ++ cfg.applyExtraFlags;

  buildFlags =
    commonFlags
    ++ mkFlag cfg.buildOnTarget "--build-on-target"
    ++ mkFlag cfg.noSubstitute "--no-substitute"
    ++ mkFlag cfg.substituteOnDestination "--substitute-on-destination"
    ++ mkFlag (!cfg.gzip) "--no-gzip"
    ++ cfg.buildExtraFlags;

  evalFlags = commonFlags ++ cfg.evalExtraFlags;

  renderFlags = flags: lib.concatStringsSep " " (map lib.escapeShellArg flags);

  mkColmenaScript =
    {
      subcommand,
      flags,
      description,
    }:
    {
      inherit description;
      args = [
        {
          name = "...";
          description = "Additional arguments passed to colmena ${subcommand}";
        }
      ];
      exec = ''
        set -euo pipefail
        exec ${lib.getExe cfg.package} ${subcommand} ${renderFlags flags} "$@"
      '';
    };

  sshConfigType = lib.types.submodule {
    options = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user for connecting to the machine.";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 22;
        description = "SSH port for connecting to the machine.";
      };

      keyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the SSH private key for this machine.";
      };
    };
  };

  machineType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional machine identifier (defaults to the attrset key).";
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-friendly machine name.";
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SSH host or hostname for the machine.";
      };

      ssh = lib.mkOption {
        type = sshConfigType;
        default = { };
        description = "SSH connection settings for the machine.";
      };

      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tags used for grouping and target selection.";
      };

      roles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Roles associated with this machine.";
      };

      provider = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Infrastructure provider name (aws, gcp, hetzner, etc.).";
      };

      arch = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Target system architecture (e.g., x86_64-linux).";
      };

      publicIp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public IPv4/IPv6 address for the machine.";
      };

      privateIp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Private IPv4/IPv6 address for the machine.";
      };

      labels = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Arbitrary labels attached to the machine.";
      };

      nixosProfile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "NixOS profile name to deploy on this machine.";
      };

      nixosModules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra NixOS modules to include for this machine.";
      };

      targetEnv = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Deployment environment label for this machine.";
      };

      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Environment variables applied to this machine.";
      };

      metadata = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Extra metadata for downstream tooling.";
      };
    };
  };

  normalizeMachines =
    machines:
    if machines == null then
      { }
    else if builtins.isString machines then
      let
        parsed = builtins.tryEval (builtins.fromJSON machines);
      in
      if parsed.success then
        normalizeMachines parsed.value
      else
        { }
    else if builtins.isList machines then
      lib.listToAttrs (
        lib.imap0 (
          idx: machine:
          let
            isAttrs = builtins.isAttrs machine;
            rawId = if isAttrs then machine.id or null else null;
            name = if isAttrs then machine.name or null else null;
            host = if isAttrs then machine.host or null else null;
            derivedId =
              if rawId != null then
                rawId
              else if name != null then
                name
              else if host != null then
                host
              else
                "machine-${toString idx}";
            base = if isAttrs then machine else { };
          in
          lib.nameValuePair derivedId (base // { id = derivedId; })
        ) machines
      )
    else if builtins.isAttrs machines then
      lib.mapAttrs (
        id: machine:
        let
          base = if builtins.isAttrs machine then machine else { };
          resolvedId = base.id or id;
        in
        base // { id = resolvedId; }
      ) machines
    else
      { };
in
{
  options.stackpanel.colmena = {
    enable = lib.mkEnableOption "Colmena deployment tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.colmena;
      description = "Colmena package to use for generated commands.";
    };

    config = lib.mkOption {
      type = lib.types.str;
      default = "colmena.nix";
      description = "Path to the Colmena hive config passed via --config.";
    };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional flake reference passed via --flake.";
    };

    on = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Node names, tags, or patterns to include with --on.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Node names, tags, or patterns to exclude with --exclude.";
    };

    keepResult = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Keep build results in the GC roots (--keep-result).";
    };

    verbose = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable verbose Colmena output (--verbose).";
    };

    showTrace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show detailed Nix traces on evaluation failures (--show-trace).";
    };

    impure = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Evaluate with impure mode enabled (--impure).";
    };

    evalNodeLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Maximum number of nodes evaluated concurrently (--eval-node-limit).";
    };

    parallel = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Maximum number of deployment jobs run concurrently (--parallel).";
    };

    buildOnTarget = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Build closures on target nodes (--build-on-target).";
    };

    uploadKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Upload deployment keys before activation (--upload-keys).";
    };

    noSubstitute = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable binary cache substitution (--no-substitute).";
    };

    substituteOnDestination = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow substitution on destination nodes (--substitute-on-destination).";
    };

    gzip = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable gzip compression for build closure transfer (use --no-gzip when false).";
    };

    reboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow Colmena to reboot machines if needed (--reboot).";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags appended to all generated Colmena commands.";
    };

    applyExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags appended to the generated colmena-apply command.";
    };

    buildExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags appended to the generated colmena-build command.";
    };

    evalExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags appended to the generated colmena-eval command.";
    };

    machineSource = lib.mkOption {
      type = lib.types.enum [
        "infra"
        "manual"
        "mixed"
      ];
      default = "infra";
      description = ''
        Source of machine inventory for Colmena.

        - infra: use stackpanel.infra.outputs.machines (authoritative)
        - manual: use manually configured machines (not yet implemented)
        - mixed: merge infra outputs with manual overrides (not yet implemented)
      '';
    };

    machinesComputed = lib.mkOption {
      type = lib.types.attrsOf machineType;
      default = { };
      readOnly = true;
      description = "Resolved machine inventory for Colmena (computed).";
    };

    computed = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      readOnly = true;
      description = "Computed Colmena flag sets for each generated command.";
    };
  };

  config = lib.mkIf (sp.enable && cfg.enable) {
    stackpanel.colmena.computed = {
      common = commonFlags;
      apply = applyFlags;
      build = buildFlags;
      eval = evalFlags;
    };

    stackpanel.colmena.machinesComputed = lib.mkDefault (
      if cfg.machineSource == "infra" then
        let
          infraOutputs = config.stackpanel.infra.outputs or { };
          moduleMachines =
            if infraOutputs ? machines && infraOutputs.machines ? machines then
              infraOutputs.machines.machines
            else if infraOutputs ? "aws-ec2" && infraOutputs."aws-ec2" ? machines then
              infraOutputs."aws-ec2".machines
            else if infraOutputs ? "aws-ec2-app" && infraOutputs."aws-ec2-app" ? machines then
              infraOutputs."aws-ec2-app".machines
            else if infraOutputs ? machines then
              infraOutputs.machines
            else
              null;
        in
        normalizeMachines moduleMachines
      else
        { }
    );

    stackpanel.devshell.packages = [
      cfg.package
    ];

    stackpanel.scripts = {
      colmena-apply = mkColmenaScript {
        subcommand = "apply";
        flags = applyFlags;
        description = "Run colmena apply with stackpanel defaults";
      };

      colmena-build = mkColmenaScript {
        subcommand = "build";
        flags = buildFlags;
        description = "Run colmena build with stackpanel defaults";
      };

      colmena-eval = mkColmenaScript {
        subcommand = "eval";
        flags = evalFlags;
        description = "Run colmena eval with stackpanel defaults";
      };
    };

    stackpanel.healthchecks.modules.${meta.id} = {
      enable = true;
      displayName = meta.name;
      checks = {
        colmena-installed = {
          description = "Colmena CLI is installed and accessible";
          script = ''
            command -v colmena >/dev/null 2>&1 && colmena --version
          '';
          severity = "critical";
          timeout = 5;
        };

        hive-config = {
          description = "Configured Colmena hive file exists";
          script = ''
            if [ -n "${if cfg.flake != null then cfg.flake else ""}" ]; then
              exit 0
            fi

            ROOT="''${STACKPANEL_ROOT:-$(pwd)}"
            test -f "$ROOT/${cfg.config}"
          '';
          severity = "warning";
          timeout = 5;
        };
      };
    };

    stackpanel.modules.${meta.id} = {
      enable = true;
      meta = {
        name = meta.name;
        description = meta.description;
        icon = meta.icon;
        category = meta.category;
        author = meta.author;
        version = meta.version;
        homepage = meta.homepage;
      };
      source.type = "builtin";
      features = meta.features;
      flakeInputs = meta.flakeInputs or [ ];
      tags = meta.tags;
      priority = meta.priority;
      healthcheckModule = meta.id;
    };
  };
}
