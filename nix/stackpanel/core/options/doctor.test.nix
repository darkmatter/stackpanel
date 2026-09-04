# ==============================================================================
# doctor.test.nix
#
# Equivalence tests for the doctor unification: the deprecated
# `stackpanel.moduleChecks` and `stackpanel.healthchecks.modules` sugar must
# produce exactly the same `moduleChecksFlattened`, `moduleChecksCertification`,
# `healthchecksComputed` and `healthchecksList` as the same checks declared
# directly under `stackpanel.doctor`.
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
        ./checks.nix
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

  legacy = evalDoctor {
    stackpanel.moduleChecks.oxlint = {
      eval = {
        description = "evaluates";
        required = true;
        derivation = evalDrv;
      };
      packages = {
        description = "packages";
        required = true;
        derivation = pkgsDrv;
      };
      custom.smoke = {
        description = "smoke";
        derivation = smokeDrv;
      };
    };
    stackpanel.healthchecks.modules.oxlint = {
      displayName = "OxLint";
      checks = {
        installed = {
          description = "installed";
          script = "command -v oxlint";
          severity = "critical";
          timeout = 5;
        };
        port = {
          type = "tcp";
          tcpHost = "localhost";
          tcpPort = 8080;
          tags = [ "net" ];
        };
      };
    };
  };

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
  json = builtins.toJSON;

  testFlattened = {
    name = "moduleChecksFlattened-identical";
    passed = json (flattenedPaths legacy) == json (flattenedPaths direct);
    got = {
      legacy = flattenedPaths legacy;
      direct = flattenedPaths direct;
    };
  };

  testCertification = {
    name = "moduleChecksCertification-identical";
    passed = json legacy.moduleChecksCertification == json direct.moduleChecksCertification;
    got = legacy.moduleChecksCertification;
  };

  testHealthchecks = {
    name = "healthchecksComputed-and-list-identical";
    passed =
      json legacy.healthchecksComputed == json direct.healthchecksComputed
      && json legacy.healthchecksList == json direct.healthchecksList;
    got = map (c: c.id) legacy.healthchecksList;
  };

  testWireShape = {
    name = "runtime-view-keeps-proto-enum-strings";
    passed =
      let
        inherit (legacy.healthchecksComputed.oxlint) installed;
      in
      installed.type == "HEALTHCHECK_TYPE_SCRIPT"
      && installed.severity == "HEALTHCHECK_SEVERITY_CRITICAL"
      && installed.timeout == 5
      && legacy.healthchecksComputed.oxlint.port.timeout == 10
      && legacy.healthchecksComputed.oxlint.port.type == "HEALTHCHECK_TYPE_TCP";
  };

  testCertificationShape = {
    name = "certification-counts-custom-checks";
    passed =
      legacy.moduleChecksCertification.oxlint.certified
      && legacy.moduleChecksCertification.oxlint.checks.customCount == 1
      && legacy.moduleChecksCertification.oxlint.missing == [ ];
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
