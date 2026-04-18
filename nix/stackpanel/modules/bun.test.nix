# ==============================================================================
# bun.test.nix
#
# Unit tests for the bun module packaging behavior. Basically, we previously
# used writeBunApplication, which copies and builds from source rather than
# deploying an artifact. This was incredibly slow. This test ensures that
# we use the hook instead, and build an artifact to deploy.
# Run with: nix eval --impure -f nix/stackpanel/modules/bun.test.nix
# ==============================================================================
let
  schema = import ./bun/schema.nix { lib = (import <nixpkgs> { }).lib; };
  # @impure — `getFlake` on a string path and `currentSystem` both require
  # --impure. This is a unit-test harness invoked manually as
  # `nix eval --impure -f nix/stackpanel/modules/bun.test.nix`, so impurity is
  # acceptable here; production evaluation does not load this file.
  flake = builtins.getFlake (toString ../../..); # @impure
  currentSystem = builtins.currentSystem; # @impure
  webPkg = flake.packages.${currentSystem}.web;
  installPhase = webPkg.drvAttrs.installPhase or "";
  nativeBuildInputs = webPkg.drvAttrs.nativeBuildInputs or [ ];

  testOutputDirField = {
    name = "output-dir-field";
    passed =
      schema.fields ? outputDir
      && (schema.fields.outputDir.default or null) == ".output";
    fieldNames = builtins.attrNames schema.fields;
    outputDirDefault = schema.fields.outputDir.default or null;
  };

  testUsesHookBackedDerivation = {
    name = "uses-hook-backed-derivation";
    passed = builtins.any (input: builtins.match ".*bun2nix-hook" (toString input) != null) nativeBuildInputs;
    inherit nativeBuildInputs;
  };

  testInstallPhaseOnlyCopiesBuildOutput = {
    name = "install-phase-copies-build-output";
    passed =
      builtins.match ".*cp -R .*\\.output/\\. .*\\$out/\\.output/.*" installPhase != null
      && builtins.match ".*cp -r \\./\\..*" installPhase == null;
    inherit installPhase;
  };

  testInstallRunsOfflineFromLockfile = {
    name = "install-runs-offline-from-lockfile";
    passed =
      let
        flags = webPkg.drvAttrs.bunInstallFlags or [ ];
      in
      builtins.elem "--offline" flags
      && builtins.elem "--frozen-lockfile" flags;
    bunInstallFlags = webPkg.drvAttrs.bunInstallFlags or [ ];
  };

  testWorkspaceLifecycleScriptsAreStripped = {
    name = "workspace-lifecycle-scripts-are-stripped";
    passed =
      let
        patchScript = webPkg.drvAttrs.postPatch or "";
      in
      builtins.match ".*preinstall.*postinstall.*prepare.*" patchScript != null;
    postPatch = webPkg.drvAttrs.postPatch or "";
  };

  allTests = [
    testOutputDirField
    testUsesHookBackedDerivation
    testInstallPhaseOnlyCopiesBuildOutput
    testInstallRunsOfflineFromLockfile
    testWorkspaceLifecycleScriptsAreStripped
  ];

  passedTests = builtins.filter (t: t.passed) allTests;
  failedTests = builtins.filter (t: !t.passed) allTests;
in
{
  total = builtins.length allTests;
  passed = builtins.length passedTests;
  failed = builtins.length failedTests;
  allPassed = builtins.length failedTests == 0;
  results = map (t: {
    name = t.name;
    passed = t.passed;
  }) allTests;
  failedDetails = failedTests;
}
