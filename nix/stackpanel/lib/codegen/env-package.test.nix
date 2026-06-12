let
  pkgs = import <nixpkgs> { };
  inherit (pkgs) lib;

  config = {
    stackpanel = {
      project.owner = "gen";
      env = {
        output-dir = "packages/gen/env";
        package-name = "@gen/env";
      };
      secrets.recipients.dev = {
        public-key = "age1example";
        tags = [ "dev" ];
      };
      users = { };
      apps.web = {
        path = "apps/web";
        environmentIds = [ "dev" ];
        env.PORT = {
          value = "3000";
        };
      };
      envs = { };
    };
  };

  envPackage = import ./env-package.nix { inherit lib config pkgs; };
  registry =
    envPackage.generatedFiles."packages/gen/env/src/runtime/generated-payloads/registry.ts".content;

  testRegistryUsesManifestTargets = {
    name = "registry-uses-manifest-targets";
    passed =
      lib.hasInfix ''"web": {'' registry
      && lib.hasInfix ''"dev": async () => (await import("./web/dev")).default'' registry
      && !(lib.hasInfix "_app" registry);
    inherit registry;
  };

  allTests = [ testRegistryUsesManifestTargets ];
  failedTests = lib.filter (t: !t.passed) allTests;
in
{
  total = lib.length allTests;
  passed = lib.length allTests - lib.length failedTests;
  failed = lib.length failedTests;
  allPassed = failedTests == [ ];
  failedDetails = failedTests;
}
