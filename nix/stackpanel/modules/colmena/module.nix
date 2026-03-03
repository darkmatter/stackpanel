#
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
#   6. Generates Colmena hive files to .stackpanel/state/colmena/
#   7. Serializes machine inventory + app deploy mapping for the agent
#
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
  mkValueFlag = flag: value: lib.optionals (value != null) [ flag (toString value) ];
  mkListFlag = flag: values: lib.optionals (values != [ ]) [ flag (lib.concatStringsSep "," values) ];

  commonFlags =
    [ "--config" cfg.config ]
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

  # ===========================================================================
  # Machine type definitions
  # ===========================================================================

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

  # ===========================================================================
  # Normalize machine inventories from various input shapes
  # ===========================================================================

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
            mName = if isAttrs then machine.name or null else null;
            mHost = if isAttrs then machine.host or null else null;
            derivedId =
              if rawId != null then
                rawId
              else if mName != null then
                mName
              else if mHost != null then
                mHost
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

  # ===========================================================================
  # Hive codegen helpers
  # ===========================================================================

  stateDir = sp.dirs.state or ".stack/profile";
  colmenaStateDir = "${stateDir}/colmena";

  # Resolve app deploy targets to machine IDs
  resolveTargets =
    targets:
    let
      allMachineIds = builtins.attrNames cfg.machinesComputed;
      matchesTag =
        pattern: machineId:
        let
          machine = cfg.machinesComputed.${machineId};
          mTags = machine.tags or [ ];
          mRoles = machine.roles or [ ];
        in
        builtins.elem pattern mTags || builtins.elem pattern mRoles || pattern == machineId;
      matchAny = pattern: builtins.filter (matchesTag pattern) allMachineIds;
    in
    lib.unique (lib.concatMap matchAny targets);

  # Build per-node Nix expression
  mkNodeNix =
    machineId: machine:
    let
      mHost = machine.host or null;
      sshUser = (machine.ssh or { }).user or "root";
      sshPort = (machine.ssh or { }).port or 22;
      nixosProfile = machine.nixosProfile or null;
      arch = machine.arch or "x86_64-linux";

      appNames = builtins.attrNames (sp.apps or { });
      appsTargeting = builtins.filter (
        appName:
        let
          appCfg = sp.apps.${appName};
          deploy = appCfg.deploy or { };
          enabled = deploy.enable or false;
          targets = deploy.targets or [ ];
          resolved = resolveTargets targets;
        in
        enabled && builtins.elem machineId resolved
      ) appNames;

      appModuleImports = lib.concatMapStringsSep "\n" (
        appName:
        let
          deploy = sp.apps.${appName}.deploy or { };
          mods = deploy.nixosModules or [ ];
        in
        lib.concatMapStringsSep "\n" (mod: "      ${mod}") mods
      ) appsTargeting;
    in
    ''
      # Generated by stackpanel colmena module — do not edit manually.
      # Machine: ${machineId}
      { name, nodes, pkgs, ... }:
      {
        deployment = {
          ${lib.optionalString (mHost != null) ''targetHost = "${mHost}";''}
          targetUser = "${sshUser}";
          ${lib.optionalString (sshPort != 22) ''targetPort = ${toString sshPort};''}
          tags = ${builtins.toJSON ((machine.tags or [ ]) ++ (machine.roles or [ ]))};
        };

        ${lib.optionalString (nixosProfile != null) ''
          imports = [
            ${nixosProfile}
            ${appModuleImports}
          ];
        ''}
        ${lib.optionalString (nixosProfile == null && appModuleImports != "") ''
          imports = [
            ${appModuleImports}
          ];
        ''}

        nixpkgs.system = "${arch}";
      }
    '';

  # Build the hive.nix that imports all nodes
  allMachineIds = builtins.attrNames cfg.machinesComputed;
  hiveNix =
    ''
      # Generated by stackpanel colmena module — do not edit manually.
      {
        meta = {
          nixpkgs = import <nixpkgs> { };
        };

    ''
    + lib.concatMapStringsSep "\n" (
      machineId:
      ''
          "${machineId}" = import ./nodes/${machineId}.nix;
      ''
    ) allMachineIds
    + ''
      }
    '';

  # Machines JSON for agent consumption
  machinesJson = builtins.toJSON (
    lib.mapAttrs (
      id: machine:
      {
        inherit id;
        name = machine.name or id;
        host = machine.host or null;
        ssh = {
          user = (machine.ssh or { }).user or "root";
          port = (machine.ssh or { }).port or 22;
          keyPath = (machine.ssh or { }).keyPath or null;
        };
        tags = machine.tags or [ ];
        roles = machine.roles or [ ];
        provider = machine.provider or null;
        arch = machine.arch or null;
        publicIp = machine.publicIp or null;
        privateIp = machine.privateIp or null;
        targetEnv = machine.targetEnv or null;
        labels = machine.labels or { };
      }
    ) cfg.machinesComputed
  );

  # App deploy mapping JSON for agent
  appDeployJson = builtins.toJSON (
    lib.filterAttrs (_: v: v.enable) (
      lib.mapAttrs (
        appName: appCfg:
        let
          deploy = appCfg.deploy or { };
        in
        {
          enable = deploy.enable or false;
          targets = deploy.targets or [ ];
          resolvedTargets = resolveTargets (deploy.targets or [ ]);
          role = deploy.role or null;
          nixosModules = deploy.nixosModules or [ ];
          system = deploy.system or null;
        }
      ) (sp.apps or { })
    )
  );
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
      default = "${colmenaStateDir}/hive.nix";
      description = "Path to the Colmena hive config passed via --config.";
    };

    generateHive = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate Colmena hive files from machinesComputed.";
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

      colmena-validate = {
        description = "Validate Colmena machine inventory and app targets";
        exec = ''
          set -euo pipefail
          echo "Colmena Validation"
          echo "=================="
          echo ""
          echo "Machine source: ${cfg.machineSource}"
          echo "Hive config:    ${cfg.config}"
          echo "Generate hive:  ${if cfg.generateHive then "yes" else "no"}"
          echo ""

          MACHINES_FILE="${stateDir}/colmena-machines.json"
          if [ -f "$MACHINES_FILE" ]; then
            COUNT=$(${pkgs.jq}/bin/jq 'length' "$MACHINES_FILE")
            echo "Machines: $COUNT"
            ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value.host // "no host") [\(.value.tags | join(", "))]"' "$MACHINES_FILE"
          else
            echo "Machines: (no state file yet)"
          fi

          echo ""
          DEPLOY_FILE="${stateDir}/colmena-app-deploy.json"
          if [ -f "$DEPLOY_FILE" ]; then
            echo "App deploy mapping:"
            ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): targets=\(.value.targets | join(",")) resolved=\(.value.resolvedTargets | join(","))"' "$DEPLOY_FILE"
          else
            echo "App deploy: (no state file yet)"
          fi
        '';
      };
    };

    # =========================================================================
    # Hive codegen: generate .stackpanel/state/colmena/{hive.nix, nodes/*.nix}
    # =========================================================================
    stackpanel.files.entries = lib.mkIf cfg.generateHive (
      {
        "${colmenaStateDir}/hive.nix" = {
          text = hiveNix;
          mode = "0644";
          description = "Generated Colmena hive (imports all nodes)";
          source = "colmena";
        };

        "${stateDir}/colmena-machines.json" = {
          text = machinesJson;
          mode = "0644";
          description = "Colmena machine inventory (JSON for agent)";
          source = "colmena";
        };

        "${stateDir}/colmena-app-deploy.json" = {
          text = appDeployJson;
          mode = "0644";
          description = "App deploy mapping (JSON for agent)";
          source = "colmena";
        };
      }
      // lib.listToAttrs (
        map (
          machineId:
          lib.nameValuePair "${colmenaStateDir}/nodes/${machineId}.nix" {
            text = mkNodeNix machineId cfg.machinesComputed.${machineId};
            mode = "0644";
            description = "Colmena node config for ${machineId}";
            source = "colmena";
          }
        ) allMachineIds
      )
    );

    # =========================================================================
    # Serialization for agent
    # =========================================================================
    stackpanel.serializable.colmena = {
      inherit (cfg) enable machineSource generateHive;
      config = cfg.config;
      machineCount = builtins.length allMachineIds;
      machineIds = allMachineIds;
    };

    # =========================================================================
    # Environment variables
    # =========================================================================
    stackpanel.devshell.env = {
      STACKPANEL_COLMENA_MACHINES = "${stateDir}/colmena-machines.json";
      STACKPANEL_COLMENA_APP_DEPLOY = "${stateDir}/colmena-app-deploy.json";
      STACKPANEL_COLMENA_HIVE = "${colmenaStateDir}/hive.nix";
    };

    # =========================================================================
    # Health checks
    # =========================================================================
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

    # =========================================================================
    # Module registration
    # =========================================================================
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
      tags = meta.tags;
      priority = meta.priority;
      healthcheckModule = meta.id;
    };
  };
}
