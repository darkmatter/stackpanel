# ==============================================================================
# doctor.test.nix
#
# Tests for the doctor surface: checks declared under `stackpanel.doctor` must
# produce the read-only views (`moduleChecksFlattened`,
# `moduleChecksCertification`, `healthchecksComputed`, `healthchecksList`) in
# the exact shapes the flake outputs and the agent API consume, and the removed
# `moduleChecks` / `healthchecks.modules` options must be rejected.
#
# Run with: nix eval --impure -f nix/stackpanel/core/options/doctor.test.nix
# ==============================================================================
let
  pkgs = import <nixpkgs> { }; # @impure test harness only
  inherit (pkgs) lib;

  evalDoctor =
    module:
    (lib.evalModules {
      modules = [
        ./doctor.nix
        ./healthchecks.nix
        ./addons.nix
        {
          options.stackpanel = {
            panels = lib.mkOption {
              type = lib.types.attrsOf lib.types.attrs;
              default = { };
            };
            scriptsConfig.packages = lib.mkOption {
              type = lib.types.attrsOf lib.types.package;
              default = { };
            };
          };
        }
        module
      ];
      specialArgs = {
        inherit pkgs;
      };
    }).config.stackpanel;

  evalDrv = pkgs.runCommand "oxlint-eval" { } "touch $out";
  pkgsDrv = pkgs.runCommand "oxlint-packages" { } "touch $out";
  smokeDrv = pkgs.runCommand "oxlint-smoke" { } "touch $out";

  direct = evalDoctor {
    stackpanel.doctor.oxlint = {
      displayName = "OxLint";
      eval = {
        scope = "build";
        description = "evaluates";
        required = true;
        derivation = evalDrv;
      };
      packages = {
        scope = "build";
        description = "packages";
        required = true;
        derivation = pkgsDrv;
      };
      smoke = {
        scope = "build";
        description = "smoke";
        derivation = smokeDrv;
      };
      installed = {
        scope = "runtime";
        description = "installed";
        script = "command -v oxlint";
        severity = "critical";
        timeout = 5;
      };
      port = {
        scope = "runtime";
        type = "tcp";
        tcpHost = "localhost";
        tcpPort = 8080;
        tags = [ "net" ];
      };
    };
  };

  # Derivations compare by drvPath so the comparison is JSON-safe.
  flattenedPaths = cfg: lib.mapAttrs (_: d: d.drvPath) cfg.moduleChecksFlattened;

  testFlattened = {
    name = "moduleChecksFlattened-keys-and-derivations";
    passed =
      builtins.attrNames (flattenedPaths direct) == [
        "oxlint-eval"
        "oxlint-packages"
        "oxlint-smoke"
      ]
      && (flattenedPaths direct).oxlint-eval == evalDrv.drvPath;
    got = flattenedPaths direct;
  };

  testCertification = {
    name = "moduleChecksCertification-shape";
    passed =
      direct.moduleChecksCertification == {
        oxlint = {
          certified = true;
          missing = [ ];
          checks = {
            eval = true;
            packages = true;
            config = false;
            integration = false;
            lint = false;
            customCount = 1;
          };
        };
      };
    got = direct.moduleChecksCertification;
  };

  testHealthchecks = {
    name = "healthchecksComputed-and-list-cover-runtime-checks";
    passed =
      builtins.attrNames direct.healthchecksComputed.oxlint == [
        "installed"
        "port"
      ]
      &&
        map (c: c.id) direct.healthchecksList == [
          "oxlint-installed"
          "oxlint-port"
        ];
    got = map (c: c.id) direct.healthchecksList;
  };

  # The removed authoring surfaces are rejected, not silently ignored.
  rejects =
    module:
    !(builtins.tryEval (builtins.seq (builtins.length (evalDoctor module).doctorList) true)).success;
  testRemovedSurfacesRejected = {
    name = "moduleChecks-and-healthchecks-modules-are-rejected";
    passed =
      rejects {
        stackpanel.moduleChecks.oxlint.eval = {
          description = "x";
          derivation = evalDrv;
        };
      }
      && rejects {
        stackpanel.healthchecks.modules.oxlint.checks.installed.script = "true";
      };
  };

  testWireShape = {
    name = "runtime-view-keeps-proto-enum-strings";
    passed =
      let
        inherit (direct.healthchecksComputed.oxlint) installed;
      in
      installed.type == "HEALTHCHECK_TYPE_SCRIPT"
      && installed.severity == "HEALTHCHECK_SEVERITY_CRITICAL"
      && installed.timeout == 5
      && direct.healthchecksComputed.oxlint.port.timeout == 10
      && direct.healthchecksComputed.oxlint.port.type == "HEALTHCHECK_TYPE_TCP";
  };

  testCertificationShape = {
    name = "certification-counts-custom-checks";
    passed =
      direct.moduleChecksCertification.oxlint.certified
      && direct.moduleChecksCertification.oxlint.checks.customCount == 1
      && direct.moduleChecksCertification.oxlint.missing == [ ];
  };

  testDoctorList = {
    name = "doctorList-covers-all-scopes";
    passed =
      let
        scopes = map (c: c.scope) direct.doctorList;
        build = builtins.filter (c: c.scope == "build") direct.doctorList;
      in
      builtins.length direct.doctorList == 5
      && builtins.elem "build" scopes
      && builtins.elem "runtime" scopes
      && builtins.all (c: c.type == "HEALTHCHECK_TYPE_DERIVATION" && c.drvPath != null) build;
  };

  # A repo-scope check is doctor-only: never in the healthcheck wire views.
  repoScoped = evalDoctor {
    stackpanel.doctor.repo-tool = {
      lockfile = {
        scope = "repo";
        script = "test -f bun.lock";
      };
    };
  };
  testRepoScope = {
    name = "repo-scope-is-doctor-only";
    passed =
      repoScoped.healthchecksList == [ ]
      && builtins.length repoScoped.doctorList == 1
      && (builtins.head repoScoped.doctorList).scope == "repo";
  };

  allTests = [
    testFlattened
    testCertification
    testHealthchecks
    testRemovedSurfacesRejected
    testWireShape
    testCertificationShape
    testDoctorList
    testRepoScope
  ];
  failedTests = builtins.filter (t: !t.passed) allTests;
in
{
  total = builtins.length allTests;
  passed = builtins.length allTests - builtins.length failedTests;
  failed = builtins.length failedTests;
  allPassed = failedTests == [ ];
  results = map (t: {
    inherit (t) name passed;
  }) allTests;
  failedDetails = failedTests;
}
