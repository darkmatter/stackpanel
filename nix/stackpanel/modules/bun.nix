# ==============================================================================
# bun.nix
#
# Bun application module for stackpanel.
#
# Automatically provides tooling and packages for Bun apps defined in
# config.stackpanel.apps with bun.enable = true.
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
  inputs,
  ...
}:
let
  cfg = config.stackpanel;

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
  generateToml =
    name: app:
    let
      goCfg = app.go;
    in
    ''
      #:schema https://json.schemastore.org/any.json
      root = "."
      tmp_dir = "tmp"
      [build]
      bin = "./tmp/${name}"
      include_ext = ["go", "tpl", "tmpl", "html", "md"]
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
    in
    pkgs.runCommand "${name}-generated-files" { } ''
      mkdir -p $out/${app.path}

      # Copy generated files from store
      cp ${packageJson} $out/${app.path}/package.json
    '';

  # Create file entries for materialization (uses stackpanel.files system)
  # Each file needs its own derivation (not a path into another derivation)
  mkGeneratedFileEntries =
    name: app:
    let
      goCfg = app.go;
      # Create individual file derivations
      packageJsonDrv = pkgs.runCommand "${name}-package.json" {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "jsonContent" ];
        jsonContent = builtins.toJSON (generatePackageJson name app);
      } ''jq '.' < "$jsonContentPath" > $out'';
    in
    {
      "${app.path}/package.json" = {
        type = "derivation";
        drv = packageJsonDrv;
      };
    };

  # Build a Go app package
  # Supports both Go workspace (root go.mod) and per-app go.mod layouts
  mkGoPackage =
    name: app:
    let
      goCfg = app.go;
      repoRoot = ../../..;
      appPath = app.path;

      # Check if app has its own go.mod (per-app layout)
      hasPerAppGoMod = builtins.pathExists (repoRoot + "/${appPath}/go.mod");
      hasPerAppGomod2nix = builtins.pathExists (repoRoot + "/${appPath}/gomod2nix.toml");

      # For per-app layout, use the app directory as source
      # For workspace layout, use repo root with subPackages
      src =
        if hasPerAppGoMod then
          repoRoot + "/${appPath}"
        # else if goCfg.generateFiles then
        #   mkGoSourceWithGenerated name app
        else
          repoRoot;

      # gomod2nix.toml location depends on layout
      bunNixPath = if hasPerAppGomod2nix then repoRoot + "/${appPath}/bun.nix" else repoRoot + "/bun.nix";
    in
    # https://nix-community.github.io/bun2nix/building-packages/writeBunApplication.html
    inputs.bun2nix.writeBunApplication {
      pname = if goCfg.binaryName != null then goCfg.binaryName else name;
      version = goCfg.version;
      # runtimeInputs = [ pkgs.go ];
      # excludeShellChecks = [];
      # extraShellCheckFlags = [];
      # bashOptions = [];
      inheritPath = false;
      packageJson = bunNixPath;
      inherit src;
      # dontUseBunBuild = true;
      # dontUseBunCheck = true;
      # runtimeEnv = {
      #   STACKPANEL_APP_PATH = app.path;
      # };
      # Rename binary if needed
      buildPhase = ''
        bun run build
      '';
      startScript = ''
        bun run start
      '';
      # https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html#arguments
      bunDeps = inputs.bun2nix.fetchBunDeps {
        bunNix = bunNixPath;
      };
    };

  # Create mkGoEnv for development
  # Supports both Go workspace (root go.mod) and per-app go.mod layouts
  mkGoDevEnv =
    name: app:
    let
      goCfg = app.go;
      repoRoot = ../../..;
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
      repoRoot = ../../..;
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
  # Option for exposing Go packages (not included in devshell)
  options.stackpanel.bun.packages = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
    description = ''
      npm packages for apps with bun.enable = true.
      These are exposed for `nix build` but NOT included in devshell.
      Access via config.stackpanel.bun.packages.apps.<name>, etc.
    '';
  };

  # Always add bun options to all apps (not conditional)
  config = lib.mkMerge [
    {
      stackpanel.appModules = [
        (
          { lib, ... }:
          {
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
                    default = [ ];
                    description = "Go linker flags";
                    example = [ "-X main.version=1.0.0" ];
                  };

                  watchDirs = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [
                      "cmd"
                      "internal"
                    ];
                    description = "Directories to watch for air live reload";
                  };

                  devArgs = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Arguments to pass to binary during development";
                    example = [
                      "serve"
                      "--port=3000"
                    ];
                  };

                  tools = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
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
              default = { };
              description = "Go-specific configuration for this app";
            };
          }
        )
      ];
    }
    (lib.mkIf (cfg.apps != { }) (
      let
        # Filter apps to only Go apps (evaluated lazily inside mkIf)
        goApps = lib.filterAttrs (name: app: app.bun.enable or false) cfg.apps;
      in
      lib.mkIf (goApps != { }) {
        # Conditionally add packages/files only for apps with go.enable = true
        # assertions = lib.mapAttrsToList (name: app: {
        #   assertion = app.path != null;
        #   message = "stackpanel.apps.${name}.path must be set when stackpanel.apps.${name}.bun.enable = true";
        # }) goApps;

        # Expose Go packages via stackpanel.bun.packages (NOT in devshell)
        # These are for `nix build` outputs, not devshell dependencies
        # Build failures here won't prevent shell entry
        stackpanel.bun.packages = {
          apps = lib.mapAttrs mkGoPackage goApps;
          devEnvs = lib.mapAttrs mkGoDevEnv goApps;
          generatedFiles = lib.mapAttrs mkGeneratedFiles goApps;
        };

        # TODO: Add test checks when stackpanel.checks option exists
        # stackpanel.bun.checks = lib.mapAttrs mkGoTests goApps;

        # Materialize generated files using stackpanel.files system
        stackpanel.files.entries = lib.mkMerge (
          lib.mapAttrsToList (
            name: app: lib.optionalAttrs app.bun.generateFiles (mkGeneratedFileEntries name app)
          ) goApps
        );

        # Add run-<app> and test-<app> wrapper commands for each Go app
        # Uses STACKPANEL_ROOT env var which is set on shell entry
        stackpanel.devshell.commands = lib.mkMerge (
          lib.mapAttrsToList (name: app: {
            "run-${name}" = {
              exec = ''cd "$STACKPANEL_ROOT/${app.path}" && exec go run ${app.bun.mainPackage} "$@"'';
              runtimeInputs = [ pkgs.go ];
            };
            "test-${name}" = {
              exec = ''cd "$STACKPANEL_ROOT/${app.path}" && exec go test ./... "$@"'';
              runtimeInputs = [ pkgs.go ];
            };
          }) goApps
        );
      }
    ))
  ];
}
