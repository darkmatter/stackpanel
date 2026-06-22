# ==============================================================================
# exports.nix
#
# Consolidated flake exports for stackpanel.
# User-facing flake construction is based on flake-parts.
# ==============================================================================
{ inputs }:
let
  stackpanelInputs = inputs;
  inherit (stackpanelInputs) nixpkgs;

  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  # Required overlays from stackpanel's inputs.
  # These are needed for building the stackpanel CLI (buildGoApplication, bun2nix)
  # and for Go 1.26-compatible developer tools.
  stackpanelOverlays = [
    stackpanelInputs.gomod2nix.overlays.default
    stackpanelInputs.bun2nix.overlays.default
    (
      final: _prev:
      let
        unstablePkgs = import stackpanelInputs.nixpkgs-unstable {
          inherit (final.stdenv.hostPlatform) system;
        };
      in
      {
        inherit (unstablePkgs) delve;
        inherit (unstablePkgs) gopls;
        inherit (unstablePkgs) gotools;
        inherit (unstablePkgs) gofumpt;
        inherit (unstablePkgs) golines;
      }
    )
  ];

  # Recursively read a directory into { "<relative path>" = <file contents>; }.
  # Used to derive lib.initFiles from the template directory so that
  # `stackpanel init` and `nix flake init -t` share one source of truth.
  dirToAttrs =
    dir:
    nixpkgs.lib.concatMapAttrs (
      name: type:
      if type == "directory" then
        nixpkgs.lib.mapAttrs' (sub: nixpkgs.lib.nameValuePair "${name}/${sub}") (
          dirToAttrs (dir + "/${name}")
        )
      else if type == "regular" then
        { ${name} = builtins.readFile (dir + "/${name}"); }
      else
        { }
    ) (builtins.readDir dir);

  initFilesFor = name: dirToAttrs (./templates + "/${name}");

  # ---------------------------------------------------------------------------
  # Addons: optional, prompt-gated extras applied by `stackpanel init`.
  #
  # Each directory under templates/_addons/<id>/ declares one addon:
  #   - addon.nix : the prompt + optional config patch + metadata
  #   - files/    : optional static files copied in when the addon is selected
  #
  # Directories whose name starts with "_" (e.g. _template) are scaffolding and
  # are never offered as real addons. `stackpanel init` reads `lib.initAddons`,
  # asks each `question`, copies the selected `files`, and patches the selected
  # `config` into .stack/config.nix.
  # ---------------------------------------------------------------------------
  addonsDir = ./templates/_addons;

  # Static files contributed by an addon, read recursively from its files/ dir.
  addonFilesFor =
    id:
    let
      filesDir = addonsDir + "/${id}/files";
    in
    if builtins.pathExists filesDir then dirToAttrs filesDir else { };

  # { "<id>" = { id; question; config ? {}; files ? {}; }; } for every live addon.
  initAddons =
    if !builtins.pathExists addonsDir then
      { }
    else
      nixpkgs.lib.mapAttrs
        (
          id: _:
          let
            spec = import (addonsDir + "/${id}/addon.nix");
          in
          spec
          // {
            id = spec.id or id;
            files = (spec.files or { }) // (addonFilesFor id);
          }
        )
        (
          nixpkgs.lib.filterAttrs (
            name: type: type == "directory" && !nixpkgs.lib.hasPrefix "_" name
          ) (builtins.readDir addonsDir)
        );

  # Function to get stackpanel options.
  # Usage: inputs.stackpanel.lib.getOptions { inherit pkgs; }
  getOptions =
    { pkgs }:
    let
      inherit (pkgs) lib;
      evaluated = lib.evalModules {
        modules = [
          ../stackpanel
          {
            _module.args = {
              inherit pkgs lib;
              inputs = { };
            };
            stackpanel.enable = true;
            stackpanel.name = "options-eval";
          }
        ];
      };
    in
    evaluated.options.stackpanel;

  # Compatibility helper for callers that still build one system manually.
  mkOutputs = args: import ./per-system-outputs.nix args;

  exported = rec {
    inherit supportedSystems;

    # ==========================================================================
    # FLAKE MODULES (for flake-parts users)
    # ==========================================================================
    flakeModules = {
      default = stackpanelInputs.flake-parts.lib.importApply ./default.nix {
        localFlake = stackpanelInputs.self;
        localInputs = stackpanelInputs;
      };
    };

    # ==========================================================================
    # LIBRARY FUNCTIONS
    # ==========================================================================
    lib = {
      inherit mkOutputs;

      # Main entry point for complete stackpanel flakes. This delegates to
      # flake-parts and imports flakeModules.default plus caller imports.
      mkFlake =
        args@{
          inputs,
          systems ? supportedSystems,
          overlays ? [ ],
          stackpanelImports ? [ ],
          imports ? [ ],
          projectRoot ? null,
          ...
        }:
        let
          callerInputs = inputs;
          flakeParts = callerInputs.flake-parts or stackpanelInputs.flake-parts;
          allOverlays = stackpanelOverlays ++ overlays;
          callerModule = builtins.removeAttrs args [
            "inputs"
            "self"
            "systems"
            "overlays"
            "stackpanelImports"
            "imports"
            "projectRoot"
          ];
          flakeOutputs = flakeParts.lib.mkFlake { inherit inputs; } (
            {
              inherit systems;
              imports = [
                exported.flakeModules.default
                callerModule
              ]
              ++ imports;
              stackpanel.imports = stackpanelImports;
              perSystem =
                { system, ... }:
                {
                  _module.args.pkgs = import callerInputs.nixpkgs {
                    inherit system;
                    overlays = allOverlays;
                  };
                };
            }
            // nixpkgs.lib.optionalAttrs (projectRoot != null) {
              stackpanel.projectRoot = projectRoot;
            }
          );
        in
        flakeOutputs
        // {
          lib = exported.lib // (flakeOutputs.lib or { });
          templates = exported.templates // (flakeOutputs.templates or { });
          flakeModules = exported.flakeModules // (flakeOutputs.flakeModules or { });
          nixosModules = exported.nixosModules // (flakeOutputs.nixosModules or { });
        };

      # Required overlays for stackpanel.
      requiredOverlays = stackpanelOverlays;

      # AWS credential helpers.
      mkAwsCredScripts = import ../stackpanel/integrations/services/aws/lib.nix;

      # Step CA certificate helpers.
      mkStepScripts = import ../stackpanel/lib/services/step.nix;

      # Fly.io OIDC to AWS authentication.
      flyOidc = import ../stackpanel/lib/services/fly-oidc.nix;

      # Get stackpanel module options for introspection.
      inherit getOptions;

      # Database schema module - contains all proto.nix schemas.
      db = import ../stackpanel/db { };

      # Init files for scaffolding new projects.
      inherit initFilesFor;
      initFiles = initFilesFor "default";
      initTemplates = {
        default = initFilesFor "default";
        minimal = initFilesFor "minimal";
      };

      # Optional, prompt-gated addons applied by `stackpanel init`. The CLI reads
      # this, asks each question, and copies files / patches config accordingly.
      inherit initAddons;

      # All schemas for codegen/introspection.
      inherit ((import ../stackpanel/db { })) schemas;
    };

    # ==========================================================================
    # NIXOS MODULES (for NixOS users)
    # ==========================================================================
    nixosModules = {
      default = ../stackpanel/default.nix;
      aws = ../stackpanel/integrations/services/aws;
      network = ../stackpanel/network/network.nix;
      secrets = ../stackpanel/secrets/default.nix;
      theme = ../stackpanel/lib/theme.nix;
      caddy = ../stackpanel/integrations/services/caddy.nix;
      ci = ../stackpanel/apps/ci.nix;
      web-service = ../stackpanel/nixos/web-service.nix;
    };

    # ==========================================================================
    # TEMPLATES
    # ==========================================================================
    templates = {
      default = {
        path = ./templates/default;
        description = "Stackpanel + flake-parts (recommended)";
      };
      minimal = {
        path = ./templates/minimal;
        description = "Stackpanel minimal setup";
      };
      example-basic = {
        path = ../../examples/basic;
        description = "Example: single app starter";
      };
      example-multi-app = {
        path = ../../examples/multi-app;
        description = "Example: monorepo with multiple apps and services";
      };
      example-cloudflare = {
        path = ../../examples/cloudflare;
        description = "Example: edge deployment config for Cloudflare";
      };
      test-basic = {
        path = ./templates/_test-fixtures/basic;
        description = "Test fixture: minimal config, no apps";
      };
      test-with-oxlint = {
        path = ./templates/_test-fixtures/with-oxlint;
        description = "Test fixture: OxLint module enabled";
      };
      test-full-stack = {
        path = ./templates/_test-fixtures/full-stack;
        description = "Test fixture: all features (multiple apps, modules)";
      };
      test-external-module = {
        path = ./templates/_test-fixtures/external-module;
        description = "Test fixture: for testing external modules";
      };
    };
  };
in
exported
