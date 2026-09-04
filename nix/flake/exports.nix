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

  # Required overlays (gomod2nix, bun2nix, unstable Go tools). Shared with the
  # flake module composer via ./overlays.nix.
  stackpanelOverlays = import ./overlays.nix { localInputs = stackpanelInputs; };

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
  # Addons: adoption offers presented by `stack setup` (and `stackpanel init`).
  # Declared under templates/_addons/<id>/addon.nix; the reader is shared with
  # the flake module so the same list is available inside evaluated projects.
  # ---------------------------------------------------------------------------
  inherit (import ./addons.nix { inherit (nixpkgs) lib; }) initAddons;

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

    # Pinned Prelude flake (null when the input is absent). Re-exported so
    # power users can `nix run` / import against the same pin Stackpanel uses.
    # Consumers of mkFlake / flakeModules.default get Prelude transitively via
    # localInputs — they do not need to add this input themselves.
    prelude = stackpanelInputs.prelude or null;

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
          # Same Prelude pin the Stackpanel flake module closes over.
          inherit (exported) prelude;
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

      # Adoption offers for `stack setup` on a fresh repo (no evaluable project
      # config yet). Inside a project the same offers arrive via stackpanel.addons.
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
