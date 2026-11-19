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
    "aarch64-darwin"
  ];

  registryFor =
    callerInputs:
    import ./integrations {
      inherit (nixpkgs) lib;
      inputs = callerInputs;
      localInputs = stackpanelInputs;
      localFlake = stackpanelInputs.self;
    };
  stackpanelOverlays = (registryFor { }).overlays;

  # Recursively read a directory into { "<relative path>" = <file contents>; }.
  # Used to derive lib.initFiles from the template directory so that
  # `stack setup` and `nix flake init -t` share one source of truth.
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
  # Addons: adoption offers presented by `stack setup`.
  # Declared under templates/_addons/<id>/addon.nix; the reader is shared with
  # the flake module so the same list is available inside evaluated projects.
  # ---------------------------------------------------------------------------
  inherit (import ./addons.nix { inherit (nixpkgs) lib; }) initAddons;

  # Function to get stackpanel options.
  # Usage: inputs.stackpanel.lib.getOptions { inherit pkgs; }
  getOptions =
    {
      pkgs,
      inputs ? { },
      self ? inputs.self or null,
      extraImports ? [ ],
      autoImportInputs ? true,
    }:
    let
      lib = import ./module-lib.nix pkgs.lib;
      evaluated = lib.evalModules {
        specialArgs = {
          inherit pkgs lib;
          inputs = import ./module-inputs.nix stackpanelInputs.self inputs;
          self = if self == null then stackpanelInputs.self else self;
          isGlobalEval = false;
          localFlake = stackpanelInputs.self;
        };
        modules = [
          ../stackpanel
          {
            stackpanel.enable = lib.mkDefault true;
            stackpanel.name = lib.mkDefault "options-eval";
          }
        ]
        ++ (import ./stackpanel-imports.nix {
          inherit
            lib
            inputs
            self
            extraImports
            autoImportInputs
            ;
        });
      };
    in
    evaluated.options.stackpanel;

  exported = rec {
    inherit supportedSystems;

    # Pinned Prelude flake (null when the input is absent). Re-exported so
    # power users can `nix run` / import against the same pin Stackpanel uses.
    # Consumers of mkFlake / flakeModules.default get Prelude transitively via
    # localInputs — they do not need to add this input themselves.
    prelude = stackpanelInputs.prelude or null;

    # Wrapped numtide/blueprint. Same call shape as `inputs.blueprint`.
    # Stackpanel's required overlays and supportedSystems are the defaults;
    # caller `nixpkgs.overlays` are appended so they win. `prefix` and any
    # other blueprint arguments pass through.
    #
    #   outputs = inputs: inputs.stackpanel.blueprint { inherit inputs; };
    blueprint =
      {
        systems ? supportedSystems,
        nixpkgs ? { },
        ...
      }@args:
      stackpanelInputs.blueprint (
        removeAttrs args [
          "nixpkgs"
          "systems"
        ]
        // {
          inherit systems;
          nixpkgs = nixpkgs // {
            overlays = (registryFor args.inputs).overlays ++ (nixpkgs.overlays or [ ]);
          };
        }
      );

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
    # DEVENV MODULES (for devenv CLI / devenv.flakeModule users)
    # ==========================================================================
    devenvModules = {
      default = import ./devenv-module.nix {
        localFlake = stackpanelInputs.self;
        localInputs = stackpanelInputs;
      };
    };

    # ==========================================================================
    # LIBRARY FUNCTIONS
    # ==========================================================================
    lib = (import ./module-lib.nix nixpkgs.lib).stackpanel // {
      # Main entry point for complete stackpanel flakes. This delegates to
      # flake-parts and imports flakeModules.default plus caller imports.
      mkFlake =
        args@{
          inputs,
          systems ? supportedSystems,
          overlays ? [ ],
          autoImportInputs ? true,
          stackpanelImports ? [ ],
          imports ? [ ],
          projectRoot ? null,
          ...
        }:
        let
          callerInputs = inputs;
          flakeParts = callerInputs.flake-parts or stackpanelInputs.flake-parts;
          callerModule = removeAttrs args [
            "inputs"
            "self"
            "systems"
            "overlays"
            "autoImportInputs"
            "stackpanelImports"
            "imports"
            "projectRoot"
          ];
          flakeOutputs = flakeParts.lib.mkFlake { inherit inputs; } ({
            inherit systems;
            imports = [
              exported.flakeModules.default
              callerModule
            ]
            ++ imports;
            stackpanel = {
              inherit overlays;
              autoImportInputs = nixpkgs.lib.mkDefault autoImportInputs;
              imports = stackpanelImports;
            }
            // nixpkgs.lib.optionalAttrs (projectRoot != null) { inherit projectRoot; };
          });
        in
        flakeOutputs;

      # Required overlays for stackpanel.
      requiredOverlays = stackpanelOverlays;

      # Get stackpanel module options for introspection.
      inherit getOptions;

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

    };

    # ==========================================================================
    # NIXOS MODULES (for NixOS users)
    # Project flakes publish only the modules generated from their own config
    # (see global-outputs.nix); these are Stackpanel's own.
    # ==========================================================================
    nixosModules = {
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
      module = {
        path = ./templates/module;
        description = "External Stackpanel module with nixd authoring support";
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
