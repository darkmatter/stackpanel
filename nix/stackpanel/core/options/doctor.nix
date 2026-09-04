# ==============================================================================
# doctor.nix - Unified observation surface
#
# `stackpanel.doctor.<module>.<name>` is the single place a module declares a
# check. Every check has a `scope`:
#
#   build   - a derivation that must succeed; consumed by `nix flake check`
#             (via the legacy `moduleChecksFlattened` view) and `stack doctor --build`
#   runtime - a probe of machine state (tools on PATH, caches, running services);
#             consumed by the agent API / studio traffic lights (via the legacy
#             `healthchecksList` view), `stackpanel healthcheck`, and `stack doctor`
#   repo    - an observation about the repository itself; consumed by `stack doctor`
#
# The doctor OBSERVES. It never installs, never writes. Repo state is fixed by
# reconciliation (`stack setup`), so a repo-scope check never needs a fix
# command; anything outside the repo (caches, browsers, credentials) is runtime
# scope and may carry a `fixCommand` hint for the user.
#
# The former `stackpanel.moduleChecks` (build) and
# `stackpanel.healthchecks.modules` (runtime) surfaces were folded into this
# option. Their computed outputs are still produced here as read-only views
# (`moduleChecksFlattened`, `moduleChecksCertification`, `healthchecksComputed`,
# `healthchecksList`) so flake outputs, the agent API and the proto enum
# strings stay byte-identical. The wire types deliberately keep their
# `Healthcheck` / `HEALTHCHECK_TYPE_*` names: the authoring surface changed,
# the wire format did not.
#
# Usage:
#   stackpanel.doctor.playwright = {
#     displayName = "Playwright";
#     browsers = {
#       scope = "runtime";
#       severity = "warning";
#       script = ''test -d "$HOME/.cache/ms-playwright"'';
#       fixCommand = "bunx playwright install";
#     };
#     eval = {
#       scope = "build";
#       required = true;
#       derivation = pkgs.runCommand "playwright-eval" { } "touch $out";
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  ...
}:
let
  cfg = config.stackpanel;

  hasPkgs = pkgs != null;

  scopeType = lib.types.enum [
    "build"
    "runtime"
    "repo"
  ];

  # Reused verbatim from the healthcheck surface.
  severityType = lib.types.enum [
    "critical" # Failing = unhealthy status (red)
    "warning" # Failing = degraded status (yellow)
    "info" # Informational only (doesn't affect status)
  ];

  detectorType = lib.types.enum [
    "script" # Shell script that returns 0 for healthy
    "nix" # Nix expression that evaluates to true/false
    "http" # HTTP endpoint check
    "tcp" # TCP port check
  ];

  # Names reserved on a doctor module for module-level metadata. Everything
  # else under `stackpanel.doctor.<module>` is a check.
  moduleMetaKeys = [
    "enable"
    "displayName"
  ];

  checkType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this check runs and is shown in reports.";
          example = false;
        };

        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name for this check in reports, the UI and the agent API.";
          example = "PostgreSQL accepts connections";
        };

        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Human-readable explanation of what this check verifies.";
          example = "Verifies the local PostgreSQL service accepts TCP connections.";
        };

        scope = lib.mkOption {
          type = scopeType;
          default = "runtime";
          description = ''
            What the check observes.

            - `build`: a derivation that must build; run by `nix flake check`.
            - `runtime`: machine state outside the repo (tools, caches, services).
            - `repo`: the repository itself. Repo state is fixed by reconciliation,
              so repo checks never carry a fix command.
          '';
          example = "runtime";
        };

        severity = lib.mkOption {
          type = severityType;
          default = "warning";
          description = ''
            How failure affects the module aggregate status.

            - `critical`: failure marks the module unhealthy (red).
            - `warning`: failure marks the module degraded (yellow).
            - `info`: failure is reported but does not affect aggregate status.
          '';
          example = "critical";
        };

        fixCommand = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Command the user can run to fix a failing runtime check. Shown verbatim
            in reports; never executed by the doctor. Repo-scope checks should not
            need one because `stack setup` reconciles repo state.
          '';
          example = "bunx playwright install";
        };

        # ── runtime / repo detectors ──────────────────────────────────────
        type = lib.mkOption {
          type = detectorType;
          default = "script";
          description = ''
            Detector for runtime and repo checks.

            - `script`: execute a shell script from `script`, `path`, `scriptRef`, or `scriptPackage`; exit code 0 is healthy.
            - `nix`: evaluate `nixExpr`; boolean true is healthy.
            - `http`: request `httpUrl` with `httpMethod`; `httpExpectedStatus` is healthy.
            - `tcp`: open a TCP connection to `tcpHost:tcpPort`; connect success is healthy.
          '';
          example = "http";
        };

        script = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Inline shell script body for `type = "script"` checks.

            The script is packaged as an executable derivation and run directly by
            the agent. Exit 0 means healthy; any non-zero exit means failed.
            Mutually exclusive with `path`, `scriptRef`, and `scriptPackage`.
          '';
          example = lib.literalExpression ''
            ''${pkgs.postgresql}/bin/pg_isready -h localhost -p "$STACKPANEL_POSTGRES_PORT"
          '';
        };

        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a shell script file for `type = "script"` checks. File content
            is read at evaluation time and packaged as an executable derivation.
            Mutually exclusive with `script`, `scriptRef`, and `scriptPackage`.
          '';
          example = lib.literalExpression "./.stack/src/checks/postgres/can-connect.sh";
        };

        scriptRef = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Name of a `stackpanel.scripts.<name>` entry to reuse for a script check.
            Mutually exclusive with `script`, `path`, and `scriptPackage`.
          '';
          example = "db-connect";
        };

        scriptPackage = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = ''
            Derivation that provides the executable for a script check. Use this when
            the check already exists as a package or needs richer packaging than
            inline `script`/`path` can provide.
          '';
          example = lib.literalExpression ''
            pkgs.writeShellScriptBin "check-db" "exec pg_isready -h localhost -p \"$STACKPANEL_POSTGRES_PORT\""
          '';
        };

        nixExpr = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Nix expression string for `type = \"nix\"` checks; true is healthy.";
          example = "builtins.pathExists ./flake.nix";
        };

        httpUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Absolute URL requested by `type = \"http\"` checks; healthy when the response status equals `httpExpectedStatus`.";
          example = "http://localhost:3000/health";
        };

        httpMethod = lib.mkOption {
          type = lib.types.str;
          default = "GET";
          description = "HTTP method used for `type = \"http\"` checks.";
          example = "HEAD";
        };

        httpExpectedStatus = lib.mkOption {
          type = lib.types.int;
          default = 200;
          description = "HTTP status code that marks a `type = \"http\"` check as healthy.";
          example = 204;
        };

        tcpHost = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Hostname or IP address connected to by `type = \"tcp\"` checks.";
          example = "localhost";
        };

        tcpPort = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "TCP port connected to by `type = \"tcp\"` checks.";
          example = 5432;
        };

        timeout = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = ''
            Maximum number of seconds before the check is marked failed.
            Defaults to 300 for build-scope checks and 10 otherwise.
          '';
          example = 5;
        };

        interval = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "How often to run this check in seconds. If null, check runs only on demand.";
        };

        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Tags used to filter or group checks in UI and agent output.";
          example = [
            "database"
            "critical"
          ];
        };

        # ── build detector ────────────────────────────────────────────────
        derivation = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "For `scope = \"build\"`: the derivation that must build successfully. Exposed under `checks.<system>.<module>-<name>`.";
          example = lib.literalExpression ''pkgs.runCommand "module-eval" {} "touch $out"'';
        };

        required = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "For `scope = \"build\"`: whether this check is required for module certification (the `eval` and `packages` checks).";
          example = true;
        };
      };
    }
  );

  doctorModuleType = lib.types.submodule (
    { name, ... }:
    {
      freeformType = lib.types.attrsOf checkType;
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable every check registered under this module key.";
          example = true;
        };

        displayName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name for this module's health summary in the UI.";
          example = "PostgreSQL";
        };
      };
    }
  );

  # ── Views over the store ───────────────────────────────────────────────

  checksOf = mod: builtins.removeAttrs mod moduleMetaKeys;

  enabledModules = lib.filterAttrs (_: mod: mod.enable) cfg.doctor;

  checksInScope = scope: mod: lib.filterAttrs (_: c: c.scope == scope) (checksOf mod);

  # Build scope --------------------------------------------------------------
  buildChecksByModule = lib.filterAttrs (_: cs: cs != { }) (
    lib.mapAttrs (_: mod: lib.filterAttrs (_: c: c.enable) (checksInScope "build" mod)) enabledModules
  );

  requireDerivation =
    moduleId: checkName: c:
    if c.derivation == null then
      throw "stackpanel.doctor.${moduleId}.${checkName}: scope = \"build\" requires `derivation`"
    else
      c.derivation;

  moduleChecksFlattened = lib.concatMapAttrs (
    moduleId: cs:
    lib.mapAttrs' (
      checkName: c: lib.nameValuePair "${moduleId}-${checkName}" (requireDerivation moduleId checkName c)
    ) cs
  ) buildChecksByModule;

  standardBuildChecks = [
    "eval"
    "packages"
    "config"
    "integration"
    "lint"
  ];

  moduleChecksCertification = lib.mapAttrs (
    _: cs:
    let
      has = n: cs ? ${n};
    in
    {
      certified = has "eval" && has "packages";
      missing = lib.optional (!has "eval") "eval" ++ lib.optional (!has "packages") "packages";
      checks = {
        eval = has "eval";
        packages = has "packages";
        config = has "config";
        integration = has "integration";
        lint = has "lint";
        customCount = builtins.length (lib.attrNames (builtins.removeAttrs cs standardBuildChecks));
      };
    }
  ) buildChecksByModule;

  # Runtime scope (legacy healthcheck wire shape) -----------------------------
  resolvedTimeout =
    c: if c.timeout != null then c.timeout else (if c.scope == "build" then 300 else 10);

  # Build script derivation for a check. All script-type checks become
  # derivations for security (no sh -c with inline content).
  mkCheckScript =
    moduleName: checkName: check:
    let
      hasScript = check.script != null;
      hasScriptRef = check.scriptRef != null;
      hasPath = check.path != null;
      hasScriptPackage = check.scriptPackage != null;

      checkName' = "${moduleName}-${checkName}";
    in
    if !hasPkgs then
      null
    else if hasScriptPackage then
      check.scriptPackage
    else if hasScriptRef then
      let
        refName = check.scriptRef;
        scriptPkgs = config.stackpanel.scriptsConfig.packages or { };
        refPkg = scriptPkgs.${refName} or null;
      in
      if refPkg == null then
        throw "Healthcheck '${checkName'}': scriptRef '${refName}' not found in stackpanel.scripts"
      else
        refPkg
    else if hasPath then
      pkgs.writeShellApplication {
        name = "healthcheck-${checkName'}";
        text = builtins.readFile check.path;
      }
    else if hasScript then
      pkgs.writeShellApplication {
        name = "healthcheck-${checkName'}";
        text = check.script;
      }
    else
      null;

  typeEnum = {
    script = "HEALTHCHECK_TYPE_SCRIPT";
    nix = "HEALTHCHECK_TYPE_NIX";
    http = "HEALTHCHECK_TYPE_HTTP";
    tcp = "HEALTHCHECK_TYPE_TCP";
  };

  severityEnum = {
    critical = "HEALTHCHECK_SEVERITY_CRITICAL";
    warning = "HEALTHCHECK_SEVERITY_WARNING";
    info = "HEALTHCHECK_SEVERITY_INFO";
  };

  # The exact record shape the agent API and studio consume today.
  serializeCheck =
    moduleName: checkName: check:
    let
      scriptDrv = mkCheckScript moduleName checkName check;

      hasScript = check.script != null;
      hasScriptRef = check.scriptRef != null;
      hasPath = check.path != null;

      sourceCount = lib.count (x: x) [
        hasScript
        hasPath
        hasScriptRef
      ];
    in
    assert
      sourceCount <= 1
      || throw "Healthcheck '${moduleName}.${checkName}': specify only one of 'script', 'path', or 'scriptRef'";
    let
      scriptSource =
        if check.scriptPackage != null then
          "package"
        else if hasScriptRef then
          "scriptRef:${check.scriptRef}"
        else if hasPath then
          "path"
        else if hasScript then
          "inline"
        else
          null;

      checkName' = "${moduleName}-${checkName}";
      scriptBinPath =
        if scriptDrv != null then
          if hasScriptRef then
            "${scriptDrv}/bin/${check.scriptRef}"
          else
            "${scriptDrv}/bin/healthcheck-${checkName'}"
        else
          null;
    in
    {
      id = "${moduleName}-${checkName}";
      inherit (check) name;
      inherit (check) description;
      type = typeEnum.${check.type};
      severity = severityEnum.${check.severity};
      script =
        if hasScript then
          check.script
        else if hasPath then
          builtins.readFile check.path
        else
          null;
      scriptPath = scriptBinPath;
      scriptDrvPath = if scriptDrv != null then builtins.toString scriptDrv.drvPath else null;
      inherit scriptSource;
      inherit (check) nixExpr;
      inherit (check) httpUrl;
      inherit (check) httpMethod;
      inherit (check) httpExpectedStatus;
      inherit (check) tcpHost;
      inherit (check) tcpPort;
      timeout = resolvedTimeout check;
      inherit (check) interval;
      module = moduleName;
      inherit (check) tags;
      enabled = check.enable;
    };

  # A module appears in the healthcheck views when it declares at least one
  # runtime check (enabled or not) - the same set the legacy
  # `healthchecks.modules` surface produced.
  runtimeModules = lib.filterAttrs (_: mod: checksInScope "runtime" mod != { }) enabledModules;

  healthchecksComputed = lib.mapAttrs (
    moduleName: mod:
    lib.mapAttrs (checkName: check: serializeCheck moduleName checkName check) (
      lib.filterAttrs (_: c: c.enable) (checksInScope "runtime" mod)
    )
  ) runtimeModules;

  healthchecksList = lib.flatten (
    lib.mapAttrsToList (_: checks: lib.mapAttrsToList (_: check: check) checks) healthchecksComputed
  );

  # All scopes (new wire for `stack doctor`) ----------------------------------
  doctorList = lib.flatten (
    lib.mapAttrsToList (
      moduleName: mod:
      lib.mapAttrsToList (
        checkName: check:
        if check.scope == "build" then
          {
            id = "${moduleName}-${checkName}";
            inherit (check) name description;
            module = moduleName;
            inherit (mod) displayName;
            scope = "build";
            severity = severityEnum.${check.severity};
            type = "HEALTHCHECK_TYPE_DERIVATION";
            checkName = "${moduleName}-${checkName}";
            drvPath = builtins.toString (requireDerivation moduleName checkName check).drvPath;
            timeout = resolvedTimeout check;
            inherit (check) tags required;
            enabled = check.enable;
            inherit (check) fixCommand;
          }
        else
          (serializeCheck moduleName checkName check)
          // {
            inherit (check) scope fixCommand;
            inherit (mod) displayName;
          }
      ) (checksOf mod)
    ) enabledModules
  );
in
{
  options.stackpanel.doctor = lib.mkOption {
    type = lib.types.attrsOf doctorModuleType;
    default = { };
    description = ''
      Checks organized by module: `stackpanel.doctor.<module>.<name>`.

      Two keys on each module are reserved for module metadata (`enable`,
      `displayName`); every other key is a check with a `scope` of `build`,
      `runtime` or `repo`. `stack doctor` runs everything declared here;
      `nix flake check` additionally consumes the `build` subset.

    '';
    example = lib.literalExpression ''
      {
        playwright = {
          displayName = "Playwright";
          browsers = {
            scope = "runtime";
            severity = "warning";
            script = "test -d \"$HOME/.cache/ms-playwright\"";
            fixCommand = "bunx playwright install";
          };
          eval = {
            scope = "build";
            required = true;
            derivation = pkgs.runCommand "playwright-eval" {} "touch $out";
          };
        };
      }
    '';
  };

  options.stackpanel.doctorList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = doctorList;
    description = "Flat list of every enabled module's checks across all scopes, serialized for `stack doctor`.";
  };

  # ── Read-only views (byte-identical to the former check surfaces) ─────────

  options.stackpanel.moduleChecksFlattened = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    readOnly = true;
    default = moduleChecksFlattened;
    description = ''
      Build-scope doctor checks flattened for the flake `checks` output.
      Keys are "<module>-<name>" (e.g., "oxlint-eval").
    '';
    example = lib.literalExpression ''
      {
        oxlint-eval = pkgs.runCommand "oxlint-eval" {} "touch $out";
        oxlint-packages = pkgs.runCommand "oxlint-packages" {} "touch $out";
      }
    '';
  };

  options.stackpanel.moduleChecksCertification = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = moduleChecksCertification;
    description = ''
      Certification status for each module with build-scope checks.
      A module is certified when it declares both an `eval` and a `packages` check.
    '';
    example = lib.literalExpression ''
      {
        oxlint = {
          certified = true;
          missing = [ ];
          checks = { eval = true; packages = true; config = false; integration = false; lint = false; customCount = 0; };
        };
      }
    '';
  };

  options.stackpanel.healthchecksComputed = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
    readOnly = true;
    default = healthchecksComputed;
    description = "Runtime-scope doctor checks grouped by module in the agent API wire shape.";
  };

  options.stackpanel.healthchecksList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = healthchecksList;
    description = "Flat list of all enabled runtime-scope checks for UI/API iteration.";
  };
}
