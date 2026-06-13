# ==============================================================================
# exports.nix
#
# Consolidated flake exports for stackpanel.
# All user-facing outputs are defined here and imported by flake.nix.
#
# Simplified architecture (flake-utils based):
#   - lib.mkFlake - generates per-system outputs using flake-utils
#   - lib.mkOutputs - generates outputs for a single system
#   - Utility functions for stackpanel configuration
# ==============================================================================
{
  inputs,
}:
let
  inherit (inputs) flake-utils nixpkgs;

  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  # Required overlays from stackpanel's inputs
  # These are needed for building the stackpanel CLI (buildGoApplication, bun2nix)
  stackpanelOverlays = [
    inputs.gomod2nix.overlays.default
    inputs.bun2nix.overlays.default
    # Go 1.26 compatible tool packages from nixpkgs-unstable.
    # Pinned nixpkgs (FlakeHub 0.2511) ships older versions that are incompatible
    # with Go 1.26 (e.g. delve 1.25.2). Remove this overlay once nixpkgs catches up.
    (
      final: _prev:
      let
        unstablePkgs = import inputs.nixpkgs-unstable {
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

  # initFilesFor: template name -> { "<relative path>" = <contents>; }
  # Defined here (not in the lib attrset) so initFiles can reference it.
  initFilesFor = name: dirToAttrs (./templates + "/${name}");

  # Function to get stackpanel options.
  # Usage: inputs.stackpanel.lib.getOptions { inherit pkgs; }
  #
  # Returns the full stackpanel options attrset for introspection.
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

  # =========================================================================
  # mkOutputs - Generate outputs for a single system
  # =========================================================================
  mkOutputs = args: import ./per-system-outputs.nix args;

in
{
  inherit supportedSystems;

  # ===========================================================================
  # LIBRARY FUNCTIONS
  # ===========================================================================
  lib = {
    # =========================================================================
    # mkOutputs - Generate outputs for a single system
    # =========================================================================
    # Lower-level function for users who want more control.
    #
    # Usage:
    #   let
    #     spOutputs = inputs.stackpanel.lib.mkOutputs {
    #       inherit pkgs inputs self system;
    #     };
    #   in {
    #     devShells.${system} = spOutputs.devShells;
    #     # ...
    #   }
    #
    inherit mkOutputs;

    # =========================================================================
    # mkFlake - Generate complete flake outputs
    # =========================================================================
    # Main entry point for users to generate stackpanel flake outputs.
    #
    # Usage:
    #   outputs = inputs.stackpanel.lib.mkFlake {
    #     inherit inputs self;
    #   };
    #
    # Or merge with additional outputs:
    #   outputs = inputs.stackpanel.lib.mkFlake { inherit inputs self; } // {
    #     packages.x86_64-linux.myPkg = ...;
    #   };
    #
    mkFlake =
      {
        inputs,
        self,
        # Optional: list of systems to build for (defaults to supportedSystems)
        systems ? supportedSystems,
        # Optional: additional overlays to apply to nixpkgs (stackpanel's overlays are always included)
        overlays ? [ ],
        # Optional: additional stackpanel module imports
        stackpanelImports ? [ ],
      }:
      let
        # Combine stackpanel's required overlays with user's overlays
        allOverlays = stackpanelOverlays ++ overlays;

        # Per-system outputs (devShells, packages, checks, apps, legacyPackages).
        # `self` is passed through so per-system-outputs.nix can derive
        # `projectRoot = toString self` for containers/infra in pure eval.
        perSystem = flake-utils.lib.eachSystem systems (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = allOverlays;
            };
          in
          mkOutputs {
            inherit
              pkgs
              inputs
              self
              system
              stackpanelImports
              ;
          }
        );

        # Global outputs (nixosModules, nixosConfigurations, colmenaHive).
        # Evaluated once using lib only — no per-system pkgs instantiation.
        globalOutputs = import ./global-outputs.nix {
          inherit inputs self stackpanelImports;
        };
      in
      perSystem // globalOutputs;

    # =========================================================================
    # Required overlays for stackpanel
    # =========================================================================
    # When using mkOutputs with custom pkgs, you must include these overlays.
    # mkFlake applies them automatically.
    requiredOverlays = stackpanelOverlays;

    # =========================================================================
    # AWS credential helpers
    # =========================================================================
    mkAwsCredScripts = import ../stackpanel/integrations/services/aws/lib.nix;

    # =========================================================================
    # Step CA certificate helpers
    # =========================================================================
    mkStepScripts = import ../stackpanel/lib/services/step.nix;

    # =========================================================================
    # Fly.io OIDC to AWS authentication
    # =========================================================================
    # Usage: inputs.stackpanel.lib.flyOidc { pkgs = pkgsLinux; }
    flyOidc = import ../stackpanel/lib/services/fly-oidc.nix;

    # =========================================================================
    # Wrap devenv input
    # =========================================================================
    # Wrap devenv input to extract schema and inject into modules.
    # This enables bidirectional mapping: devenv options <-> stackpanel state
    #
    # Usage in your flake.nix:
    #   let
    #     wrappedDevenv = inputs.stackpanel.lib.wrapDevenv { inherit inputs; };
    #   in {
    #     devShells.default = wrappedDevenv.lib.mkShell { ... };
    #     # Access schema: wrappedDevenv.schema
    #   }
    #
    # The wrapped devenv:
    #   - Extracts available services, languages, pre-commit hooks
    #   - Injects schema via specialArgs to all modules
    #   - Exposes schema for state.json serialization
    wrapDevenv = import ../lib/wrap-devenv.nix;

    # =========================================================================
    # Get stackpanel module options
    # =========================================================================
    # Usage: inputs.stackpanel.lib.getOptions { inherit pkgs; }
    inherit getOptions;

    # =========================================================================
    # DB Schema and Scaffolding
    # =========================================================================

    # Database schema module - contains all proto.nix schemas
    # Usage: inputs.stackpanel.lib.db
    db = import ../stackpanel/db { };

    # Init files for scaffolding new projects.
    #
    # DERIVED — never hand-list files here. The template directory
    # nix/flake/templates/<name>/ is the single source of truth, shared
    # byte-for-byte with `nix flake init -t`. Any file added to the template
    # automatically flows into `stackpanel init`.
    #
    # Returns a map of relative paths to file contents:
    #   { "flake.nix" = "..."; ".stack/config.nix" = "..."; ... }
    #
    # Usage from CLI:
    #   nix eval git+ssh://git@github.com/darkmatter/stackpanel#lib.initFiles --json
    #
    # Usage from Nix:
    #   inputs.stackpanel.lib.initFiles
    inherit initFilesFor;
    initFiles = initFilesFor "default";

    # All schemas for codegen/introspection
    # Usage: inputs.stackpanel.lib.schemas
    inherit ((import ../stackpanel/db { })) schemas;
  };

  # ===========================================================================
  # NIXOS MODULES (for NixOS users)
  # ===========================================================================
  nixosModules = {
    default = ./modules/devenv.nix;
    aws = ../stackpanel/integrations/services/aws;
    network = ../stackpanel/network/network.nix;
    secrets = ../stackpanel/secrets/default.nix;
    theme = ../stackpanel/lib/theme.nix;
    caddy = ../stackpanel/integrations/services/caddy.nix;
    ci = ../stackpanel/apps/ci.nix;
    web-service = ../stackpanel/nixos/web-service.nix;
  };

  # ===========================================================================
  # DEVENV MODULES (for devenv users - yaml and standalone)
  # ===========================================================================
  # Usage in devenv.shells.default:
  #   imports = [ inputs.stackpanel.devenvModules.default ];
  devenvModules = {
    default = ./modules/devenv.nix;
    # Alias for backwards compatibility
    devshell = ./modules/devenv.nix;
  };

  # ===========================================================================
  # TEMPLATES
  # ===========================================================================
  templates = {
    default = {
      path = ./templates/default;
      description = "Stackpanel + flake-utils (recommended)";
    };
    minimal = {
      path = ./templates/minimal;
      description = "Stackpanel minimal setup";
    };
    # =========================================================================
    # Examples (review-friendly template variants)
    # =========================================================================
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
    # =========================================================================
    # Test Fixtures (for module authors and CI testing)
    # =========================================================================
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
}
