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
# Go registers a lazy appBuildProviders.go.<name> package for app-build. Dev
# environments and generated file derivations stay under go.packages; they are
# not pulled into the devshell or the serialized project state.
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
  self,
  ...
}@args:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  # Unified field definitions - single source of truth for Go per-app options
  goSchema = import ./schema.nix { inherit lib; };
  inherit (lib.stackpanel) spField;
  goApps = lib.filterAttrs (_: app: app.go.enable) cfg.apps;
  hasGoApps = goApps != { };
  moduleEnabled = cfg.modules.${meta.id}.enable;
  binaryNameFor = name: go: if go.binaryName == null then name else go.binaryName;

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
      inherit name;
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
      repoRoot = self.outPath;
      generatedFiles = mkGeneratedFiles name app;
    in
    pkgs.runCommand "${name}-src-with-generated" { } ''
      # Copy repo
      cp -r ${repoRoot} $out
      chmod -R +w $out

      # Overlay generated files
      cp -r ${generatedFiles}/${app.path}/* $out/${app.path}/
    '';

  flattenJsonSetOps =
    prefix: value:
    if builtins.isAttrs value then
      lib.flatten (lib.mapAttrsToList (key: nested: flattenJsonSetOps (prefix ++ [ key ]) nested) value)
    else
      [
        {
          op = "set";
          path = prefix;
          inherit value;
        }
      ];

  # Create file entries for materialization (uses stackpanel.files system)
  # package.json uses source-aware json-ops so tracked files can be patched
  # safely during preflight without replacing unrelated user content.
  mkGeneratedFileEntries =
    name: app:
    let

      airTomlDrv = pkgs.writeText "${name}-air.toml" (generateAirToml name app);
      toolsGoDrv = pkgs.writeText "${name}-tools.go" (generateToolsGo name app);
    in
    {
      "${app.path}/package.json" = {
        module = meta.id;
        format = "json";
        writer = "paths";
        adopt = "backup";
        ops = flattenJsonSetOps [ ] (generatePackageJson name app);
        source = "go";
        description = "Go app package.json (scripts, dependencies)";
      };
      "${app.path}/.air.toml" = {
        module = meta.id;
        format = "derivation";
        drv = airTomlDrv;
      };
      "${app.path}/tools.go" = {
        module = meta.id;
        format = "derivation";
        drv = toolsGoDrv;
      };
    };

  # Build a Go app package
  # Supports both Go workspace (root go.mod) and per-app go.mod layouts
  mkGoPackage =
    name: app:
    let
      goCfg = app.go;
      repoRoot = self.outPath;
      appPath = app.path;

      # Check if app has its own go.mod (per-app layout)
      hasPerAppGoMod = builtins.pathExists (repoRoot + "/${appPath}/go.mod");
      hasPerAppGomod2nix = builtins.pathExists (repoRoot + "/${appPath}/gomod2nix.toml");

      # Keep sibling modules available for local replace directives. pwd selects
      # the module for gomod2nix; modRoot selects it inside the unpacked source.
      src = if !hasPerAppGoMod && goCfg.generateFiles then mkGoSourceWithGenerated name app else repoRoot;
      pwd = if hasPerAppGoMod then repoRoot + "/${appPath}" else repoRoot;
      finalBinaryName = binaryNameFor name goCfg;

      # gomod2nix.toml location depends on layout
      gomod2nixPath =
        if hasPerAppGomod2nix then
          repoRoot + "/${appPath}/gomod2nix.toml"
        else
          repoRoot + "/gomod2nix.toml";
    in
    pkgs.buildGoApplication {
      pname = name;
      inherit (goCfg) version;
      inherit src pwd finalBinaryName;
      modRoot = if hasPerAppGoMod then appPath else ".";

      modules = gomod2nixPath;
      # gomod2nix builds relative to modRoot. Select the app's single entrypoint.
      subPackages = [ (if hasPerAppGoMod then goCfg.mainPackage else "${appPath}/${goCfg.mainPackage}") ];

      # CGO with tree-sitter needs the macOS SDK for libresolv + frameworks
      nativeBuildInputs =
        lib.optionals pkgs.stdenv.isDarwin [
          pkgs.apple-sdk_15
        ]
        ++ lib.optionals (goCfg.runtimeInputs != [ ]) [
          pkgs.makeWrapper
        ];

      doCheck = false; # Tests run separately via checks

      ldflags = [
        "-s"
        "-w"
      ]
      ++ goCfg.ldflags;

      postInstall =
        # Go names a binary after its import path, which need not match the
        # app key. Install it under the name advertised to nix run and systemd.
        ''
          if [[ ! -x "$out/bin/$finalBinaryName" ]]; then
            bins=("$out/bin/"*)
            if [[ ''${#bins[@]} != 1 || ! -f "''${bins[0]}" || ! -x "''${bins[0]}" ]]; then
              echo "Expected one Go executable in $out/bin" >&2
              exit 1
            fi
            mv -- "''${bins[0]}" "$out/bin/$finalBinaryName"
          fi
        ''
        # Wrap binary to prepend runtimeInputs bin/ dirs to PATH
        + lib.optionalString (goCfg.runtimeInputs != [ ]) ''
          wrapProgram "$out/bin/$finalBinaryName" \
            --prefix PATH : ${lib.makeBinPath goCfg.runtimeInputs}
        '';

      meta = with lib; {
        description = goCfg.description or "${name} application";
        mainProgram = finalBinaryName;
        license = licenses.mit;
      };
    };

  # Create mkGoEnv for development
  # Supports both Go workspace (root go.mod) and per-app go.mod layouts
  mkGoDevEnv =
    _name: app:
    let
      repoRoot = self.outPath;
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

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.go.packages = lib.genAttrs [ "devEnvs" "generatedFiles" "tests" ] (
    kind:
    lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.package;
      default = { };
      description = "Go ${kind} derivations, keyed by app name; not added to the devshell.";
    }
  );

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # App options and registry metadata exist even when no project app opts in.
    {
      stackpanel.appRuntimes.${meta.id} = {
        label = meta.name;
        inherit (meta) icon;
      };
      stackpanel.modules.${meta.id} = {
        enable = lib.mkDefault hasGoApps;
        meta = {
          inherit (meta)
            name
            description
            icon
            category
            author
            version
            homepage
            ;
        };
        source.type = "builtin";
        inherit (meta) features tags priority;
        flakeInputs = meta.flakeInputs or [ ];
        healthcheckModule = meta.id;
      };
      stackpanel.lazyNamespaces = [ "go" ];

      stackpanel.appModules = [
        (
          {
            lib,
            config,
            name,
            ...
          }:
          {
            options.go = lib.mkOption {
              type = lib.types.submodule {
                options = lib.mapAttrs (_: spField.asOption) goSchema.fields // {
                  runtimeInputs = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [ ];
                    description = ''
                      Runtime packages whose bin/ directories are prepended to PATH
                      when this app's binary runs. Two effects:

                        1. Nix build: makeWrapper wraps the binary so the installed
                           binary finds the tools without a devshell.
                        2. DevShell: the packages are added to the shell so
                           go run . also finds them.

                      Example (in .stack/modules/):
                        stackpanel.apps.my-cli.go.runtimeInputs = [ pkgs.colmena ];
                    '';
                    example = lib.literalExpression "[ pkgs.colmena pkgs.git ]";
                  };
                };
              };
              default = { };
              description = ''
                Go-specific configuration for this app.

                Enables Go package builds, Air dev config, generated package.json,
                tools.go, test checks, and optional runtime PATH wrapping.
              '';
            };
            config.deployment.resolvedCommand = lib.mkIf (config.go.enable && moduleEnabled) (
              lib.mkDefault (
                { pkgs, inputs, ... }:
                "${
                  inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.${name}
                }/bin/${binaryNameFor name config.go}"
              )
            );
          }
        )
      ];
    }
    (lib.mkIf (!(args.isGlobalEval or false)) {
      stackpanel.checks = lib.mapAttrs' (
        name: drv: lib.nameValuePair "${name}-test" (lib.mkDefault drv)
      ) cfg.go.packages.tests;
    })
    (lib.mkIf (hasGoApps && moduleEnabled && !(args.isGlobalEval or false)) {
      stackpanel.appBuildProviders.${meta.id} = lib.mapAttrs mkGoPackage goApps;
      stackpanel.go.packages = {
        devEnvs = lib.mapAttrs mkGoDevEnv goApps;
        generatedFiles = lib.mapAttrs mkGeneratedFiles goApps;
      };

      # Add runtimeInputs from all Go apps to the devshell so that
      # `go run .` finds the same tools that the installed binary has wrapped in.
      stackpanel.modulePackages.${meta.id} = lib.concatMap (app: app.go.runtimeInputs) (
        lib.attrValues goApps
      );

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
            module = meta.id;
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
            module = meta.id;
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
      stackpanel.doctor.${meta.id} = {
        enable = true;
        displayName = meta.name;
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
            [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 21 ]; }
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
    })
  ];
}
