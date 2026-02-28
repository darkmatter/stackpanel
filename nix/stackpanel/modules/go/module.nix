# ==============================================================================
# module.nix - Go Module Implementation
#
# Go application module for stackpanel.
#
# Automatically provides tooling and packages for Go apps defined in
# config.stackpanel.apps with go.enable = true.
#
# Prerequisites:
#   - Root go.mod at repository root (monorepo/workspace style)
#   - Single gomod2nix.toml at root (generated via: gomod2nix generate)
#   - Apps are subpackages (e.g., apps/stackpanel-go)
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
#   stackpanel.apps.stackpanel-go = {
#     path = "apps/stackpanel-go";  # Path relative to repo root
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
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;

  # Unified field definitions - single source of truth for Go per-app options
  goSchema = import ./schema.nix { inherit lib; };
  sp = import ../../db/lib/field.nix { inherit lib; };

  # Compute npm scope prefix from config (project.repo or name)
  # e.g., "stackpanel" -> "@stackpanel"
  prefix = cfg.project.repo or cfg.name;

  # Generate package.json for a Go app
  generatePackageJson =
    name: app:
    let
      goCfg = app.go;
    in
    {
      name = name;
      private = true;
      dependencies = {
        "@${prefix}/scripts" = "workspace:*";
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
  generateAirToml =
    name: app:
    let
      goCfg = app.go;
    in
    ''
      #:schema https://json.schemastore.org/any.json

      # Air configuration for ${name} development
      # Run `air` in this directory for live reload
      # See: https://github.com/air-verse/air

      root = "."
      tmp_dir = "tmp"

      [build]
      # Run go mod tidy, then gomod2nix only if go.sum changed, then build
      cmd = """
      go mod tidy && \
      HASH=$(md5 -q go.sum 2>/dev/null || md5sum go.sum | cut -d' ' -f1) && \
      if [ ! -f tmp/.go.sum.hash ] || [ "$HASH" != "$(cat tmp/.go.sum.hash)" ]; then \
        echo 'go.sum changed, running gomod2nix...' && \
        gomod2nix && \
        echo "$HASH" > tmp/.go.sum.hash; \
      fi && \
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
  generateToolsGo =
    name: app:
    let
      goCfg = app.go;
    in
    ''
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
  mkGeneratedFiles =
    name: app:
    let
      goCfg = app.go;

      # Generate package.json as formatted JSON derivation
      packageJson =
        pkgs.runCommand "${name}-package.json"
          {
            nativeBuildInputs = [ pkgs.jq ];
            passAsFile = [ "jsonContent" ];
            jsonContent = builtins.toJSON (generatePackageJson name app);
          }
          ''
            jq '.' < "$jsonContentPath" > $out
          '';

      # Generate .air.toml as text file
      airToml = pkgs.writeText "${name}-air.toml" (generateAirToml name app);

      # Generate tools.go as text file
      toolsGo = pkgs.writeText "${name}-tools.go" (generateToolsGo name app);
    in
    pkgs.runCommand "${name}-generated-files" { } ''
      mkdir -p $out/${app.path}

      # Copy generated files from store
      cp ${packageJson} $out/${app.path}/package.json
      cp ${airToml} $out/${app.path}/.air.toml
      cp ${toolsGo} $out/${app.path}/tools.go
    '';

  # Create enhanced source that includes generated files
  mkGoSourceWithGenerated =
    name: app:
    let
      goCfg = app.go;
      repoRoot = ../../../..;
      generatedFiles = mkGeneratedFiles name app;
    in
    pkgs.runCommand "${name}-src-with-generated" { } ''
      # Copy repo
      cp -r ${repoRoot} $out
      chmod -R +w $out

      # Overlay generated files
      cp -r ${generatedFiles}/${app.path}/* $out/${app.path}/
    '';

  # Create file entries for materialization (uses stackpanel.files system)
  # package.json uses type="json" for deep-merge support from other modules
  mkGeneratedFileEntries =
    name: app:
    let
      goCfg = app.go;

      airTomlDrv = pkgs.writeText "${name}-air.toml" (generateAirToml name app);
      toolsGoDrv = pkgs.writeText "${name}-tools.go" (generateToolsGo name app);
    in
    {
      "${app.path}/package.json" = {
        type = "json";
        jsonValue = generatePackageJson name app;
        source = "go";
        description = "Go app package.json (scripts, dependencies)";
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
  # Supports both Go workspace (root go.mod) and per-app go.mod layouts
  # Consults app.build.* fields first, falling back to auto-detection
  mkGoPackage =
    name: app:
    let
      goCfg = app.go;
      buildCfg = app.build or {};
      repoRoot = ../../../..;
      appPath = app.path;

      # Layout: explicit build.srcLayout > auto-detect from go.mod presence
      hasPerAppGoMod = builtins.pathExists (repoRoot + "/${appPath}/go.mod");
      layout =
        if buildCfg.srcLayout or null != null
        then buildCfg.srcLayout
        else if hasPerAppGoMod
        then "standalone"
        else "workspace";

      isStandalone = layout == "standalone";

      # Source: explicit build.srcRoot > inferred from layout
      src =
        if buildCfg.srcRoot or null != null
        then repoRoot + "/${buildCfg.srcRoot}"
        else if isStandalone
        then repoRoot + "/${appPath}"
        else if goCfg.generateFiles
        then mkGoSourceWithGenerated name app
        else repoRoot;

      # Lockfile: explicit build.depsLockfile > inferred from layout
      hasPerAppGomod2nix = builtins.pathExists (repoRoot + "/${appPath}/gomod2nix.toml");
      gomod2nixPath =
        if buildCfg.depsLockfile or null != null
        then repoRoot + "/${buildCfg.depsLockfile}"
        else if isStandalone && hasPerAppGomod2nix
        then repoRoot + "/${appPath}/gomod2nix.toml"
        else repoRoot + "/gomod2nix.toml";

      # Output name: explicit build.outputName > go.binaryName > app name
      pname =
        if (buildCfg.outputName or null) != null then buildCfg.outputName
        else if goCfg.binaryName != null then goCfg.binaryName
        else name;
      version =
        if (buildCfg.outputVersion or null) != null then buildCfg.outputVersion
        else goCfg.version;

      # Binary rename target (if binaryName is set and differs from pname)
      effectiveBinaryName = goCfg.binaryName;
    in
    pkgs.buildGoApplication {
      inherit pname version src;

      modules = gomod2nixPath;
      # For standalone layout, build from current dir; for workspace, specify subpackage
      subPackages = if isStandalone then [ "." ] else [ appPath ];

      doCheck = false; # Tests run separately via checks

      ldflags = [
        "-s"
        "-w"
      ]
      ++ goCfg.ldflags;

      # Rename binary if needed
      postInstall = lib.optionalString (effectiveBinaryName != null) ''
        # For standalone layout, binary name is the directory name
        # For workspace layout, binary name is the last path component
        oldName=${
          if isStandalone then "$(basename ${appPath})" else lib.last (lib.splitString "/" appPath)
        }
        mv $out/bin/$oldName $out/bin/${effectiveBinaryName} 2>/dev/null || true
      '';

      meta = with lib; {
        description = goCfg.description or "${name} application";
        license = licenses.mit;
      };
    };

  # Create mkGoEnv for development
  # Supports both Go workspace (root go.mod) and per-app go.mod layouts
  mkGoDevEnv =
    name: app:
    let
      goCfg = app.go;
      repoRoot = ../../../..;
      appPath = app.path;

      # Check if app has its own go.mod (per-app layout)
      hasPerAppGoMod = builtins.pathExists (repoRoot + "/${appPath}/go.mod");
      hasPerAppGomod2nix = builtins.pathExists (repoRoot + "/${appPath}/gomod2nix.toml");

      pwd = if hasPerAppGoMod then repoRoot + "/${appPath}" else repoRoot;

      gomod2nixPath =
        if hasPerAppGomod2nix then
          repoRoot + "/${appPath}/gomod2nix.toml"
        else
          repoRoot + "/gomod2nix.toml";
    in
    pkgs.mkGoEnv {
      inherit pwd;
      modules = gomod2nixPath;
    };

  # Create test package (assumes root go.mod)
  mkGoTests =
    name: app:
    let
      goCfg = app.go;
      repoRoot = ../../../..;
    in
    pkgs.runCommand "${name}-tests"
      {
        nativeBuildInputs = [ pkgs.go ];
      }
      ''
        cd ${repoRoot}/${app.path}
        go test -v ./... > $out
      '';
in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  # Go packages are exposed via a separate option to avoid conflicts with the
  # stackpanel.modules attrsOf type
  options.stackpanel.go.packages = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
    description = ''
      Go packages for apps with go.enable = true.
      These are exposed for `nix build` but NOT included in devshell.
      Access via config.stackpanel.go.packages.apps.<name>, etc.
    '';
  };

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # Always add go options to all apps (not conditional)
    # Options are auto-generated from go-app.proto.nix (single source of truth)
    {
      stackpanel.appModules = [
        (
          { lib, ... }:
          {
            options.go = lib.mkOption {
              type = lib.types.submodule {
                options = lib.mapAttrs (_: sp.asOption) goSchema.fields;
              };
              default = { };
              description = "Go-specific configuration for this app";
            };
          }
        )
      ];
    }
    # Go app outputs - computed lazily inside config block to avoid recursion
    (
      let
        # Filter apps to only Go apps
        # NOTE: Access cfg.apps here inside the config block, not at module top-level
        goApps = lib.filterAttrs (name: app: app.go.enable or false) cfg.apps;
        hasGoApps = goApps != { };
      in
      lib.mkIf hasGoApps {
        # Expose Go packages via stackpanel.go.packages (NOT in devshell)
        # These are for `nix build` outputs, not devshell dependencies
        # Build failures here won't prevent shell entry
        stackpanel.go.packages = {
          apps = lib.mapAttrs mkGoPackage goApps;
          devEnvs = lib.mapAttrs mkGoDevEnv goApps;
          generatedFiles = lib.mapAttrs mkGeneratedFiles goApps;
          tests = lib.mapAttrs mkGoTests goApps;
        };

        # Materialize generated files using stackpanel.files system
        stackpanel.files.entries = lib.mkMerge (
          lib.mapAttrsToList (
            name: app: lib.optionalAttrs app.go.generateFiles (mkGeneratedFileEntries name app)
          ) goApps
        );

        # Add run-<app> and test-<app> wrapper scripts for each Go app
        # Uses STACKPANEL_ROOT env var which is set on shell entry
        stackpanel.scripts = lib.mkMerge (
          lib.mapAttrsToList (name: app: {
            "run-${name}" = {
              exec = ''cd "$STACKPANEL_ROOT/${app.path}" && exec go run ${app.go.mainPackage} "$@"'';
              runtimeInputs = [ pkgs.go ];
              description = "Run ${name} Go app";
              args = [
                {
                  name = "...";
                  description = "Arguments passed to the Go app";
                }
              ];
            };
            "test-${name}" = {
              exec = ''cd "$STACKPANEL_ROOT/${app.path}" && exec go test ./... "$@"'';
              runtimeInputs = [ pkgs.go ];
              description = "Test ${name} Go app";
              args = [
                {
                  name = "...";
                  description = "Arguments passed to go test";
                }
              ];
            };
          }) goApps
        );

        # Register healthchecks for Go module
        # These verify the Go development environment is properly configured
        stackpanel.healthchecks.modules.${meta.id} = {
          enable = true;
          displayName = meta.name;
          checks = {
            go-installed = {
              name = "Go Installed";
              description = "Verify Go compiler is available in PATH";
              type = "script";
              script = "command -v go >/dev/null 2>&1";
              severity = "critical";
              timeout = 5;
              tags = [
                "toolchain"
                "compiler"
              ];
            };
            go-version = {
              name = "Go Version";
              description = "Verify Go version is 1.21 or newer";
              type = "script";
              script = ''
                version=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | sed 's/go//')
                major=$(echo "$version" | cut -d. -f1)
                minor=$(echo "$version" | cut -d. -f2)
                [ "$major" -gt 1 ] || ([ "$major" -eq 1 ] && [ "$minor" -ge 21 ])
              '';
              severity = "warning";
              timeout = 5;
              tags = [
                "toolchain"
                "version"
              ];
            };
            gomod2nix-installed = {
              name = "gomod2nix Available";
              description = "Verify gomod2nix tool is available for Nix builds";
              type = "script";
              script = "command -v gomod2nix >/dev/null 2>&1";
              severity = "warning";
              timeout = 5;
              tags = [
                "nix"
                "tooling"
              ];
            };
          };
        };

        # Register module
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
      }
    )
  ];
}
