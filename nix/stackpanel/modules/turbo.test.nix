# ==============================================================================
# turbo.test.nix
#
# Unit tests for the turbo.nix module.
# Run with: nix eval -f nix/stackpanel/modules/turbo.test.nix
# ==============================================================================
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  # Minimal module system evaluation
  evalModules =
    modules:
    lib.evalModules {
      modules = modules ++ [
        # Mock the core options that turbo.nix depends on
        {
          options.stackpanel = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            appModules = lib.mkOption {
              type = lib.types.listOf lib.types.deferredModule;
              default = [ ];
            };
            apps = lib.mkOption {
              type = lib.types.attrsOf lib.types.attrs;
              default = { };
            };
            tasks = lib.mkOption {
              type = lib.types.attrsOf lib.types.attrs;
              default = { };
            };
            tasksComputed = lib.mkOption {
              type = lib.types.attrsOf lib.types.unspecified;
              default = { };
            };
            taskModules = lib.mkOption {
              type = lib.types.listOf lib.types.deferredModule;
              default = [ ];
            };
            files.entries = lib.mkOption {
              type = lib.types.attrsOf lib.types.attrs;
              default = { };
            };
            devshell.packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
            motd.commands = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [ ];
            };
          };
        }
      ];
      specialArgs = {
        inherit pkgs;
      };
    };

  # ---------------------------------------------------------------------------
  # Test: Basic turbo config generation
  # ---------------------------------------------------------------------------
  testBasicConfig =
    let
      result = evalModules [
        ./turbo.nix
        {
          config.stackpanel.tasks = {
            build = {
              exec = "echo build";
              description = "Build the project";
              outputs = [
                "dist/**"
                ".next/**"
              ];
              inputs = [ "$TURBO_DEFAULT$" ];
            };
            test = {
              exec = "vitest run";
              dependsOn = [ "build" ];
              outputs = [ "coverage/**" ];
            };
            dev = {
              persistent = true;
              cache = false;
            };
          };
        }
      ];
      turboConfig = result.config.stackpanel.turbo.config;
    in
    {
      name = "basic-config";
      passed =
        # Check schema is present
        turboConfig."$schema" == "https://turbo.build/schema.json"
        # Check ui is set
        && turboConfig.ui == "tui"
        # Check build task has outputs
        && turboConfig.tasks.build.outputs == [
          "dist/**"
          ".next/**"
        ]
        # Check test task has dependsOn
        && turboConfig.tasks.test.dependsOn == [ "build" ]
        # Check dev task has persistent and cache
        && turboConfig.tasks.dev.persistent == true
        && turboConfig.tasks.dev.cache == false;
      config = turboConfig;
    };

  # ---------------------------------------------------------------------------
  # Test: Reverse dependency computation (before -> dependsOn)
  # ---------------------------------------------------------------------------
  testReverseDeps =
    let
      result = evalModules [
        ./turbo.nix
        {
          config.stackpanel.tasks = {
            deps = {
              exec = "npm install";
              before = [
                "build"
                "test"
              ]; # deps should run before build and test
            };
            build = {
              exec = "npm run build";
            };
            test = {
              exec = "npm test";
            };
          };
        }
      ];
      turboConfig = result.config.stackpanel.turbo.config;
    in
    {
      name = "reverse-deps";
      passed =
        # build should have deps in dependsOn (from deps.before = ["build"])
        lib.elem "deps" (turboConfig.tasks.build.dependsOn or [ ])
        # test should have deps in dependsOn (from deps.before = ["test"])
        && lib.elem "deps" (turboConfig.tasks.test.dependsOn or [ ]);
      buildDeps = turboConfig.tasks.build.dependsOn or [ ];
      testDeps = turboConfig.tasks.test.dependsOn or [ ];
    };

  # ---------------------------------------------------------------------------
  # Test: Task script generation
  # ---------------------------------------------------------------------------
  testScriptGeneration =
    let
      result = evalModules [
        ./turbo.nix
        {
          config.stackpanel.tasks = {
            build = {
              exec = "echo 'building'";
              runtimeInputs = [ pkgs.nodejs ];
            };
            dev = {
              # No exec - should not generate script
              persistent = true;
            };
          };
        }
      ];
      scripts = result.config.stackpanel.turbo.scripts;
    in
    {
      name = "script-generation";
      passed =
        # build should have a script (has exec)
        scripts ? build
        # dev should NOT have a script (no exec)
        && !(scripts ? dev);
      scriptNames = lib.attrNames scripts;
    };

  # ---------------------------------------------------------------------------
  # Test: File entries generation
  # ---------------------------------------------------------------------------
  testFileEntries =
    let
      result = evalModules [
        ./turbo.nix
        {
          config.stackpanel.tasks = {
            build = {
              exec = "echo build";
            };
          };
        }
      ];
      files = result.config.stackpanel.files.entries;
    in
    {
      name = "file-entries";
      passed =
        # turbo.json should be generated
        files ? "turbo.json"
        # .tasks/bin/build symlink should be generated
        && files ? ".tasks/bin/build";
      fileNames = lib.attrNames files;
      turboJsonType = files."turbo.json".type or "missing";
      symlinkType = files.".tasks/bin/build".type or "missing";
    };

  # ---------------------------------------------------------------------------
  # Test: Package.json scripts generation
  # ---------------------------------------------------------------------------
  testPackageJsonScripts =
    let
      result = evalModules [
        ./turbo.nix
        {
          config.stackpanel.tasks = {
            build = {
              exec = "echo build";
            };
            test = {
              exec = "vitest";
            };
            dev = {
              # No exec
              persistent = true;
            };
          };
        }
      ];
      scripts = result.config.stackpanel.turbo.packageJsonScripts;
    in
    {
      name = "package-json-scripts";
      passed =
        # build and test should have package.json scripts
        scripts ? build
        && scripts ? test
        # dev should NOT (no exec)
        && !(scripts ? dev)
        # Scripts should point to .tasks/bin/
        && scripts.build == "./.tasks/bin/build"
        && scripts.test == "./.tasks/bin/test";
      scripts = scripts;
    };

  # ---------------------------------------------------------------------------
  # Test: Combined after + before dependencies
  # ---------------------------------------------------------------------------
  testCombinedDeps =
    let
      result = evalModules [
        ./turbo.nix
        {
          config.stackpanel.tasks = {
            deps = {
              exec = "npm install";
              before = [ "build" ]; # deps runs before build
            };
            typecheck = {
              exec = "tsc";
              before = [ "build" ]; # typecheck runs before build
            };
            build = {
              exec = "npm run build";
              dependsOn = [ "lint" ]; # build depends on lint
            };
            lint = {
              exec = "eslint";
            };
          };
        }
      ];
      turboConfig = result.config.stackpanel.turbo.config;
      buildDeps = turboConfig.tasks.build.dependsOn or [ ];
    in
    {
      name = "combined-deps";
      passed =
        # build should depend on: lint (from after), deps (from deps.before), typecheck (from typecheck.before)
        lib.elem "lint" buildDeps
        && lib.elem "deps" buildDeps
        && lib.elem "typecheck" buildDeps;
      buildDeps = buildDeps;
    };

  # ---------------------------------------------------------------------------
  # Run all tests
  # ---------------------------------------------------------------------------
  allTests = [
    testBasicConfig
    testReverseDeps
    testScriptGeneration
    testFileEntries
    testPackageJsonScripts
    testCombinedDeps
  ];

  passedTests = lib.filter (t: t.passed) allTests;
  failedTests = lib.filter (t: !t.passed) allTests;

  summary = {
    total = lib.length allTests;
    passed = lib.length passedTests;
    failed = lib.length failedTests;
    allPassed = lib.length failedTests == 0;
    results = map (t: {
      name = t.name;
      passed = t.passed;
    }) allTests;
    failedDetails = failedTests;
  };
in
summary
