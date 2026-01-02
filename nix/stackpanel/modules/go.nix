# ==============================================================================
# go.nix
#
# Go application module for stackpanel.
#
# Automatically provides tooling and packages for Go apps defined in
# config.stackpanel.apps with go.enable = true.
#
# Prerequisites:
#   - Root go.mod at repository root (monorepo/workspace style)
#   - Single gomod2nix.toml at root (generated via: gomod2nix generate)
#   - Apps are subpackages (e.g., apps/cli, apps/agent)
#
# Architecture:
#   Generated files (package.json, .air.toml, tools.go) are created as
#   derivations, ensuring hermetic builds with proper dependency ordering.
#   Files are materialized via stackpanel.files system during shell entry.
#
# Features per Go app:
#   - Packaged app with buildGoApplication (for distribution)
#   - Development environment with mkGoEnv (for go run/test/build)
#   - Derivation-based file generation (hermetic, can be build dependencies)
#   - File materialization via stackpanel.files for IDE/tooling support
#   - Test package for flake checks
#
# App definition example:
#   stackpanel.apps.cli = {
#     path = "apps/cli";          # Path relative to repo root
#     go = {
#       enable = true;
#       binaryName = "stackpanel";  # Rename binary (optional)
#       ldflags = [ "-s" "-w" ];    # Optional linker flags
#       generateFiles = true;       # Generate package.json, .air.toml, tools.go
#     };
#   };
#
# Generated outputs:
#   - packages.<name>: Built Go binary (with generated files if enabled)
#   - packages.<name>-dev: mkGoEnv for development
#   - packages.<name>-generated-files: Derivation with generated files
#   - checks.<name>-tests: Go tests
#
# File Materialization:
#   Generated files are materialized via stackpanel.files.entries.
#   Use `write-files` command to manually regenerate files.
#   Files are automatically written on shell entry.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel;
  util = import ../lib/util.nix { inherit pkgs lib; };

  # Generate package.json for a Go app
  generatePackageJson = name: app: let
    goCfg = app.go;
  in {
    name = name;
    private = true;
    dependencies = {
      "@stackpanel/scripts" = "workspace:*";
    };
    scripts = {
      preinstall = "check-devshell";
      deps = "go mod tidy && gomod2nix generate --with-deps";
      postinstall = "bun run deps";
      lint = "golangci-lint run ./...";
      format = "gofumpt -l -w .";
      test = "go test -v ./...";
      build = "bun run deps && go build -ldflags \"-s -w\" -o ./build/${name} ${goCfg.mainPackage}";
      dev = "air";
    };
  };

  # Generate .air.toml for a Go app
  generateAirToml = name: app: let
    goCfg = app.go;
  in ''
    #:schema https://json.schemastore.org/any.json

    # Air configuration for ${name} development
    # Run `air` in this directory for live reload
    # See: https://github.com/air-verse/air

    root = "."
    tmp_dir = "tmp"

    [build]
    # Run go mod tidy, then gomod2nix only if go.sum changed, then build
    cmd = """
    go mod tidy && \\
    HASH=$(md5 -q go.sum 2>/dev/null || md5sum go.sum | cut -d' ' -f1) && \\
    if [ ! -f tmp/.go.sum.hash ] || [ "$HASH" != "$(cat tmp/.go.sum.hash)" ]; then \\
      echo 'go.sum changed, running gomod2nix...' && \\
      gomod2nix && \\
      echo "$HASH" > tmp/.go.sum.hash; \\
    fi && \\
    go build -o ./tmp/${name} ${goCfg.mainPackage}
    """
    bin = "./tmp/${name}"
    include_ext = ["go", "tpl", "tmpl", "html", "md"]
    include_dir = ${builtins.toJSON goCfg.watchDirs}
    exclude_dir = ["tmp", "vendor", ".git", "build"]
    exclude_file = []
    exclude_unchanged = false
    follow_symlink = false
    delay = 200
    stop_on_error = true
    send_interrupt = false
    kill_delay = 500
    args_bin = ${builtins.toJSON goCfg.devArgs}
    rerun = false
    rerun_delay = 500

    [log]
    time = false
    main_only = false

    [color]
    main = "magenta"
    watcher = "cyan"
    build = "yellow"
    runner = "green"

    [misc]
    clean_on_exit = true
  '';

  # Generate tools.go for tracking tool dependencies
  generateToolsGo = name: app: let
    goCfg = app.go;
  in ''
    //go:build tools
    // +build tools

    // Package tools tracks tool dependencies for ${name}.
    // This file is used to declare tool dependencies that are not imported
    // in production code, but are needed for development/build.
    //
    // Run: go mod tidy
    // Then: gomod2nix generate --with-deps
    package tools

    import (
      _ "github.com/air-verse/air"
      _ "github.com/golangci/golangci-lint/cmd/golangci-lint"
      _ "mvdan.cc/gofumpt"
      ${lib.concatMapStringsSep "\n  " (tool: "_ \"${tool}\"") goCfg.tools}
    )
  '';

  # Create derivation with generated files (hermetic, can be a build dependency)
  mkGeneratedFiles = name: app: let
    goCfg = app.go;

    # Generate package.json as formatted JSON derivation
    packageJson = pkgs.runCommand "${name}-package.json" {
      nativeBuildInputs = [ pkgs.jq ];
      passAsFile = [ "jsonContent" ];
      jsonContent = builtins.toJSON (generatePackageJson name app);
    } ''
      jq '.' < "$jsonContentPath" > $out
    '';

    # Generate .air.toml as text file
    airToml = pkgs.writeText "${name}-air.toml" (generateAirToml name app);

    # Generate tools.go as text file
    toolsGo = pkgs.writeText "${name}-tools.go" (generateToolsGo name app);
  in pkgs.runCommand "${name}-generated-files" {} ''
    mkdir -p $out/${app.path}

    # Copy generated files from store
    cp ${packageJson} $out/${app.path}/package.json
    cp ${airToml} $out/${app.path}/.air.toml
    cp ${toolsGo} $out/${app.path}/tools.go
  '';

  # Create enhanced source that includes generated files
  mkGoSourceWithGenerated = name: app: let
    goCfg = app.go;
    repoRoot = ../../..;
    generatedFiles = mkGeneratedFiles name app;
  in pkgs.runCommand "${name}-src-with-generated" {} ''
    # Copy repo
    cp -r ${repoRoot} $out
    chmod -R +w $out

    # Overlay generated files
    cp -r ${generatedFiles}/${app.path}/* $out/${app.path}/
  '';

  # Create file entries for materialization (uses stackpanel.files system)
  # Each file needs its own derivation (not a path into another derivation)
  mkGeneratedFileEntries = name: app: let
    goCfg = app.go;
    # Create individual file derivations
    packageJsonDrv = pkgs.runCommand "${name}-package.json" {
      nativeBuildInputs = [ pkgs.jq ];
      passAsFile = [ "jsonContent" ];
      jsonContent = builtins.toJSON (generatePackageJson name app);
    } ''jq '.' < "$jsonContentPath" > $out'';
    
    airTomlDrv = pkgs.writeText "${name}-air.toml" (generateAirToml name app);
    toolsGoDrv = pkgs.writeText "${name}-tools.go" (generateToolsGo name app);
  in {
    "${app.path}/package.json" = {
      type = "derivation";
      drv = packageJsonDrv;
    };
    "${app.path}/.air.toml" = {
      type = "derivation";
      drv = airTomlDrv;
    };
    "${app.path}/tools.go" = {
      type = "derivation";
      drv = toolsGoDrv;
    };
  };

  # Build a Go app package
  # Uses source with generated files if generation is enabled
  mkGoPackage = name: app: let
    goCfg = app.go;
    repoRoot = ../../..;
    appPath = app.path;
    # Use generated source if file generation is enabled, otherwise use raw repo
    src = if goCfg.generateFiles
          then mkGoSourceWithGenerated name app
          else repoRoot;
    # Look for gomod2nix.toml in app directory (per-app), fallback to repo root
    gomod2nixPath = if builtins.pathExists (repoRoot + "/${appPath}/gomod2nix.toml")
                    then src + "/${appPath}/gomod2nix.toml"
                    else src + "/gomod2nix.toml";
  in pkgs.buildGoApplication {
    pname = name;
    version = goCfg.version;
    inherit src;

    modules = gomod2nixPath;
    subPackages = [ app.path ];  # e.g., "apps/cli"

    doCheck = false;  # Tests run separately via checks

    ldflags = [
      "-s"
      "-w"
    ] ++ goCfg.ldflags;

    # Rename binary if needed (e.g., cli -> stackpanel)
    postInstall = lib.optionalString (goCfg.binaryName != null) ''
      mv $out/bin/${lib.last (lib.splitString "/" app.path)} $out/bin/${goCfg.binaryName}
    '';

    meta = with lib; {
      description = goCfg.description or "${name} application";
      license = licenses.mit;
    };
  };

  # Create mkGoEnv for development
  mkGoDevEnv = name: app: let
    goCfg = app.go;
    repoRoot = ../../..;
    appPath = app.path;
    # Look for gomod2nix.toml in app directory (per-app), fallback to repo root
    gomod2nixPath = if builtins.pathExists (repoRoot + "/${appPath}/gomod2nix.toml")
                    then repoRoot + "/${appPath}/gomod2nix.toml"
                    else repoRoot + "/gomod2nix.toml";
    # Use app directory as pwd if it has go.mod
    pwd = if builtins.pathExists (repoRoot + "/${appPath}/go.mod")
          then repoRoot + "/${appPath}"
          else repoRoot;
  in pkgs.mkGoEnv {
    inherit pwd;
    modules = gomod2nixPath;
  };

  # Create test package (assumes root go.mod)
  mkGoTests = name: app: let
    goCfg = app.go;
    repoRoot = ../../..;
  in pkgs.runCommand "${name}-tests" {
    nativeBuildInputs = [ pkgs.go ];
  } ''
    cd ${repoRoot}/${app.path}
    go test -v ./... > $out
  '';

in {
  # Always add go options to all apps (not conditional)
  config = lib.mkMerge [
    {
      stackpanel.appModules = [
      ({ lib, ... }: {
        options.go = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable Go app support for this app";
            };

            mainPackage = lib.mkOption {
              type = lib.types.str;
              default = ".";
              description = "Go main package path";
            };

            version = lib.mkOption {
              type = lib.types.str;
              default = "0.1.0";
              description = "App version";
            };

            binaryName = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Binary name (if different from app name)";
              example = "stackpanel";
            };

            ldflags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Go linker flags";
              example = [ "-X main.version=1.0.0" ];
            };

            watchDirs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "cmd" "internal" ];
              description = "Directories to watch for air live reload";
            };

            devArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Arguments to pass to binary during development";
              example = [ "serve" "--port=3000" ];
            };

            tools = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Additional Go tool dependencies";
              example = [ "github.com/golangci/golangci-lint/cmd/golangci-lint" ];
            };

            generateFiles = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to generate package.json, .air.toml, and tools.go";
            };

            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "App description";
            };
          };
        };
        default = {};
        description = "Go-specific configuration for this app";
      };
    })
      ];
    }
    (lib.mkIf (cfg.apps != {}) (let
    # Filter apps to only Go apps (evaluated lazily inside mkIf)
    goApps = lib.filterAttrs (name: app: app.go.enable or false) cfg.apps;
  in lib.mkIf (goApps != {}) {
    # Conditionally add packages/files only for apps with go.enable = true
    # assertions = lib.mapAttrsToList (name: app: {
    #   assertion = app.path != null;
    #   message = "stackpanel.apps.${name}.path must be set when stackpanel.apps.${name}.go.enable = true";
    # }) goApps;

    stackpanel.packages = lib.attrValues (
      (lib.mapAttrs mkGoPackage goApps)
      // (lib.mapAttrs' (name: app:
        lib.nameValuePair "${name}-dev" (mkGoDevEnv name app)
      ) goApps)
      // (lib.mapAttrs' (name: app:
        lib.nameValuePair "${name}-generated-files" (mkGeneratedFiles name app)
      ) goApps));

    # TODO: Add test checks when stackpanel.checks option exists
    # stackpanel.checks = lib.mapAttrs' (name: app:
    #   lib.nameValuePair "${name}-tests" (mkGoTests name app)
    # ) goApps;

    # Materialize generated files using stackpanel.files system
    stackpanel.files.entries = lib.mkMerge (
      lib.mapAttrsToList (name: app:
        lib.optionalAttrs app.go.generateFiles (mkGeneratedFileEntries name app)
      ) goApps);

    # add IDE support
    # stackpanel.ide.vscode.settings.
  }))
  ];
}
