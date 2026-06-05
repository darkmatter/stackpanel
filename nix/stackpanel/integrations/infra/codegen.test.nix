# ==============================================================================
# infra/codegen.test.nix
#
# Unit tests for infra package codegen.
# Run with: nix eval --impure -f nix/stackpanel/infra/codegen.test.nix
# ==============================================================================
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  evalModules =
    modules:
    lib.evalModules {
      modules = modules ++ [
        ../.
        {
          _module.args.pkgs = pkgs;
          stackpanel.name = "test";
          stackpanel.infra = {
            enable = true;
            output-dir = "packages/infra";
            package.name = "@stackpanel/infra";
          };
        }
      ];
      specialArgs = {
        inherit pkgs;
      };
    };

  result = evalModules [ ];
  packageOps = result.config.stackpanel.files.entries."packages/infra/package.json".ops or [ ];

  testInfraPackageDoesNotExposeGenericDev =
    let
      hasAlchemyDev = lib.any (
        op:
        op.op == "set"
        && op.path == [
          "scripts"
          "alchemy:dev"
        ]
        && op.value == "alchemy dev"
      ) packageOps;
      removesGenericDev = lib.any (
        op:
        op.op == "remove"
        && op.path == [
          "scripts"
          "dev"
        ]
      ) packageOps;
    in
    {
      name = "infra-package-does-not-expose-generic-dev";
      passed = hasAlchemyDev && removesGenericDev;
      inherit hasAlchemyDev removesGenericDev packageOps;
    };

  allTests = [
    testInfraPackageDoesNotExposeGenericDev
  ];

  passedTests = lib.filter (t: t.passed) allTests;
  failedTests = lib.filter (t: !t.passed) allTests;
in
{
  total = lib.length allTests;
  passed = lib.length passedTests;
  failed = lib.length failedTests;
  allPassed = lib.length failedTests == 0;
  results = map (t: {
    name = t.name;
    passed = t.passed;
  }) allTests;
  failedDetails = failedTests;
}
