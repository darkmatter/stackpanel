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
#   6. Generates Colmena hive files to .stack/state/colmena/
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

  commonFlags = [
    "--config"
    cfg.config
  ]
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
        description = ''
          SSH user for connecting to the machine.

          Used for generated Colmena deployment targets. Defaults to `root`, the
          standard NixOS deployment user.
        '';
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = 22;
        description = ''
          SSH port for connecting to the machine.

          Set when hosts expose SSH on a non-default port.
        '';
        example = 2222;
      };
      keyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path to the SSH private key for this machine.

          Null lets SSH use the user's agent/config. Prefer null for developer
          machines and explicit paths for CI deploy identities.
        '';
        example = "~/.ssh/id_ed25519_deploy";
      };
    };
  };

  machineType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Optional stable machine identifier.

          Defaults to the attrset key. Use when upstream infra IDs differ from the
          Colmena node name.
        '';
      };
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Human-friendly machine name shown in generated metadata and UI panels.
        '';
        example = "Production web server";
      };
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SSH host or hostname for the machine.

          Prefer DNS names for persistent servers; IPs are fine for short-lived
          preview or lab machines.
        '';
        example = "prod-1.example.com";
      };
      ssh = lib.mkOption {
        type = sshConfigType;
        default = { };
        description = ''
          SSH connection settings for the machine.

          Contains user, port, and optional key path used to build Colmena target
          metadata.
        '';
      };
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Tags used for grouping and target selection.

          Use with Colmena `--on @tag` style targeting or UI filters.
        '';
        example = [
          "prod"
          "web"
        ];
      };
      roles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Roles associated with this machine, such as `web`, `db`, or `worker`.

          Roles describe intended function; tags describe selection/grouping.
        '';
        example = [
          "web"
          "worker"
        ];
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
        description = ''
          Arbitrary labels attached to the machine for UI, filtering, and downstream tooling.

          Labels are string key/value pairs and do not affect Colmena semantics by
          themselves.
        '';
        example = {
          region = "iad";
          size = "small";
        };
      };
      nixosProfile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          NixOS profile name to deploy on this machine.

          Use when downstream deploy tooling distinguishes multiple system
          profiles per host.
        '';
        example = "system";
      };
      nixosModules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Extra NixOS module references to include for this machine.

          This inventory shape stores strings for portability from infra outputs;
          concrete deferred modules belong in stackpanel.deployment.machines.*.modules.
        '';
        example = [ "./nixos/common.nix" ];
      };
      targetEnv = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Deployment environment label for this machine.

          Common values are `prod`, `staging`, and `preview`; used by UI and
          deploy mapping logic.
        '';
        example = "prod";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Non-secret environment variables associated with this machine.

          Intended for generated deploy metadata; app secrets should remain in
          Stackpanel env/secrets declarations.
        '';
        example = {
          REGION = "iad";
        };
      };
      metadata = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Extra machine metadata for downstream tooling.

          Use for provider IDs, regions, instance classes, or other structured
          facts not modeled by first-class options.
        '';
        example = {
          providerId = "i-abc123";
        };
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
      if parsed.success then normalizeMachines parsed.value else { }
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
          ${lib.optionalString (sshPort != 22) "targetPort = ${toString sshPort};"}
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
  hiveNix = ''
    # Generated by stackpanel colmena module — do not edit manually.
    {
      meta = {
        nixpkgs = import <nixpkgs> { };
      };

  ''
  + lib.concatMapStringsSep "\n" (machineId: ''
    "${machineId}" = import ./nodes/${machineId}.nix;
  '') allMachineIds
  + ''
    }
  '';

  # Machines JSON for agent consumption
  machinesJson = builtins.toJSON (
    lib.mapAttrs (id: machine: {
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
    }) cfg.machinesComputed
  );

  # App deploy mapping JSON for agent
  appDeployJson = builtins.toJSON (
    lib.filterAttrs (_: v: v.enable) (
      lib.mapAttrs (
        _appName: appCfg:
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
      description = ''
        Colmena package used by generated deploy/eval/build commands.

        Override to pin a patched Colmena build while keeping command generation
        unchanged.
      '';
      example = lib.literalExpression "pkgs.colmena";
    };

    config = lib.mkOption {
      type = lib.types.str;
      default = "${colmenaStateDir}/hive.nix";
      description = ''
        Path to the generated Colmena hive config passed via `--config`.

        Relative paths are resolved from project root. Leave default unless a
        repo already owns a custom hive file.
      '';
      example = ".stack/gen/colmena/hive.nix";
    };

    generateHive = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Generate Colmena hive files from machinesComputed.

        Disable only when using a hand-written hive and `stackpanel.colmena.config`
        points at that file.
      '';
      example = false;
    };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional flake reference passed via `--flake`.

        Null lets generated commands use the hive config path. Set for native
        Colmena flake workflows such as `.#colmenaHive` or `./deploy`.
      '';
      example = ".#colmenaHive";
    };

    on = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Node names, tags, or patterns included with Colmena `--on`.

        Use to constrain generated apply/build/eval commands to a subset of the
        hive, for example `[ "web-1" "@prod" ]`.
      '';
      example = [
        "@prod"
        "web-1"
      ];
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Node names, tags, or patterns excluded with Colmena `--exclude`.

        Useful for temporarily skipping a host without changing machine inventory.
      '';
      example = [ "canary-1" ];
    };

    keepResult = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep build results in GC roots with Colmena `--keep-result`.

        Useful while debugging deploy builds or when another process needs the
        result symlink after command completion.
      '';
      example = true;
    };

    verbose = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable verbose Colmena output with `--verbose`.

        Useful for deploy debugging; keep false for normal operator commands.
      '';
      example = true;
    };

    showTrace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Show detailed Nix traces on evaluation failures with `--show-trace`.

        Useful when debugging module evaluation errors in generated hives.
      '';
      example = true;
    };

    impure = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Evaluate with impure mode enabled (`--impure`).

        Keep false by default. Enable only for legacy deploy flakes that still
        read ambient environment or host paths during evaluation.
      '';
      example = false;
    };

    evalNodeLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        Maximum number of nodes evaluated concurrently with `--eval-node-limit`.

        Null omits the flag. Set a lower number for memory-constrained machines.
      '';
      example = 4;
    };

    parallel = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        Maximum number of deployment jobs run concurrently with `--parallel`.

        Null lets Colmena choose its default. Lower it for bandwidth or CPU-bound
        deploy targets.
      '';
      example = 2;
    };

    buildOnTarget = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Build closures on target nodes with `--build-on-target`.

        Enable when deploy targets have faster builders or when local builders
        cannot build the target system.
      '';
      example = true;
    };

    uploadKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Upload deployment keys before activation with `--upload-keys`.

        Enable only when the hive defines Colmena deployment keys.
      '';
      example = true;
    };

    noSubstitute = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable binary cache substitution with `--no-substitute`.

        Use for debugging local builds or when cache usage is intentionally blocked.
      '';
      example = true;
    };

    substituteOnDestination = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow substitution on destination nodes with `--substitute-on-destination`.

        Useful when target machines have cache access and should fetch closures
        directly instead of receiving all paths from the deploy host.
      '';
      example = true;
    };

    gzip = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable gzip compression for build closure transfer.

        When false, generated commands pass `--no-gzip`. Keep true for slower
        networks; disable on fast LANs when CPU overhead matters more.
      '';
      example = false;
    };

    reboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow Colmena to reboot machines if needed with `--reboot`.

        Enable for kernel/system upgrades where activation may require restart.
      '';
      example = true;
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra flags appended to all generated Colmena commands.

        Use for flags Stackpanel does not model directly. Prefer first-class
        options above for common flags.
      '';
      example = [ "--show-trace" ];
    };

    applyExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra flags appended only to the generated colmena-apply command.

        Use for apply-specific switches that should not affect build/eval.
      '';
      example = [ "--no-keys" ];
    };

    buildExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra flags appended only to the generated colmena-build command.

        Use for build-specific switches or experiments.
      '';
      example = [ "--keep-result" ];
    };

    evalExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra flags appended only to the generated colmena-eval command.

        Useful for evaluation debugging without changing apply/build behavior.
      '';
      example = [ "--show-trace" ];
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
      example = "infra";
    };

    machinesComputed = lib.mkOption {
      type = lib.types.attrsOf machineType;
      default = { };
      description = ''
        Read-only resolved machine inventory for Colmena.

        Computed from the selected machineSource and normalized to machineType so
        generated hives and UI panels consume one shape.
      '';
    };

    computed = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = ''
        Read-only computed Colmena flag sets for generated commands.

        Contains common/apply/build/eval flag lists after options such as on,
        exclude, showTrace, parallel, and extraFlags are resolved.
      '';
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
            else
              infraOutputs.machines or null;
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
    # Hive codegen: generate .stack/state/colmena/{hive.nix, nodes/*.nix}
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
      inherit (cfg) config;
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
          script =
            let
              flakeValue = if cfg.flake != null then cfg.flake else "";
            in
            ''
              FLAKE_REF="${flakeValue}"
              if [ -n "$FLAKE_REF" ]; then
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
        inherit (meta) name;
        inherit (meta) description;
        inherit (meta) icon;
        inherit (meta) category;
        inherit (meta) author;
        inherit (meta) version;
        inherit (meta) homepage;
      };
      source.type = "builtin";
      inherit (meta) features;
      inherit (meta) tags;
      inherit (meta) priority;
      healthcheckModule = meta.id;
    };
  };
}
