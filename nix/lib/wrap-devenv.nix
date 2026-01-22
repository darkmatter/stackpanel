# ==============================================================================
# wrap-devenv.nix
#
# Wraps the devenv input to:
# 1. Pre-extract available options (services, pre-commit hooks, languages)
# 2. Inject this schema into all module evaluations via specialArgs
# 3. Expose schema for serialization to state.json
#
# This enables bidirectional mapping in stackpanel modules:
#   READ:  devenvSchema.services → stackpanel.devenvServices.available (UI shows list)
#   WRITE: stackpanel.devenvServices.enabled → config.services.*.enable (apply to devenv)
#
# IMPORTANT: Schema extraction is LAZY - it only happens when you access
# `wrappedDevenv.schema` or call `wrappedDevenv.lib.mkShell`. This avoids
# slowing down flake evaluation when wrap-devenv is imported but not used.
#
# Usage in flake.nix:
#   let
#     wrappedDevenv = import ./nix/lib/wrap-devenv.nix { inherit inputs; };
#   in {
#     devShells.default = wrappedDevenv.lib.mkShell { ... };
#   }
# ==============================================================================
{ inputs }:
let
  inherit (inputs) nixpkgs;
  lib = nixpkgs.lib;
  devenv = inputs.devenv;

  # ==========================================================================
  # LAZY SCHEMA EXTRACTION
  # The schema is only computed when accessed (Nix is lazy by default)
  # ==========================================================================

  # Helper to safely extract description from option
  getDescription =
    opt: default:
    if opt ? description then
      if builtins.isString opt.description then
        opt.description
      else
        opt.description.text or default
    else
      default;

  # This function extracts the schema - only called when schema is accessed
  extractSchema =
    let
      # Evaluate devenv with minimal config to get options tree
      devenvEval = devenv.lib.mkEval {
        inherit inputs;
        modules = [ ];
      };

      devenvOptions = devenvEval.options;

      # -------------------------------------------------------------------------
      # Extract pre-commit hooks
      # -------------------------------------------------------------------------
      preCommitHooksRaw = devenvOptions.pre-commit.hooks or { };

      preCommitHooks = lib.mapAttrsToList (
        name: hookOpts:
        let
          enableOpt = hookOpts.enable or { };
        in
        {
          id = name;
          name = name;
          description = getDescription enableOpt "Enable ${name} hook";
          isBuiltin = hookOpts ? entry && hookOpts.entry ? default;
          hasFiles = hookOpts ? files;
          hasTypes = hookOpts ? types;
        }
      ) (lib.filterAttrs (n: v: builtins.isAttrs v) preCommitHooksRaw);

      # -------------------------------------------------------------------------
      # Extract services
      # -------------------------------------------------------------------------
      servicesRaw = devenvOptions.services or { };

      services = lib.mapAttrsToList (
        name: svcOpts:
        let
          enableOpt = svcOpts.enable or { };
        in
        {
          id = name;
          name = name;
          description = getDescription enableOpt "Enable ${name}";
          hasPort = svcOpts ? port || (svcOpts ? settings && svcOpts.settings ? port);
          hasPackage = svcOpts ? package;
          hasSettings = svcOpts ? settings;
        }
      ) (lib.filterAttrs (n: v: builtins.isAttrs v && v ? enable) servicesRaw);

      # -------------------------------------------------------------------------
      # Extract languages
      # -------------------------------------------------------------------------
      languagesRaw = devenvOptions.languages or { };

      languages = lib.mapAttrsToList (
        name: langOpts:
        let
          enableOpt = langOpts.enable or { };
        in
        {
          id = name;
          name = name;
          description = getDescription enableOpt "Enable ${name}";
          hasVersion = langOpts ? version;
          hasPackage = langOpts ? package;
        }
      ) (lib.filterAttrs (n: v: builtins.isAttrs v && v ? enable) languagesRaw);

    in
    {
      preCommit = {
        hooks = preCommitHooks;
        count = builtins.length preCommitHooks;
      };
      services = {
        items = services;
        count = builtins.length services;
      };
      languages = {
        items = languages;
        count = builtins.length languages;
      };
      _meta = {
        extractedAt = "build-time";
      };
    };

  # ==========================================================================
  # DEVENV INTEGRATION MODULES
  # These are included automatically when using the wrapped lib
  # ==========================================================================
  devenvIntegrationModules = [
    ../stackpanel/modules/devenv-services.nix
    ../stackpanel/modules/devenv-languages.nix
    ../stackpanel/modules/devenv-pre-commit.nix
  ];

  # ==========================================================================
  # WRAPPED LIB
  # Injects schema via specialArgs and includes integration modules
  # ==========================================================================
  wrappedLib = devenv.lib // {
    # Override mkShell to inject devenvSchema and include integration modules
    mkShell =
      args:
      let
        # Only extract schema when mkShell is actually called
        schema = extractSchema;
      in
      devenv.lib.mkShell (
        args
        // {
          specialArgs = (args.specialArgs or { }) // {
            devenvSchema = schema;
          };
          modules = devenvIntegrationModules ++ (args.modules or [ ]);
        }
      );

    # Override mkEval similarly
    mkEval =
      args:
      let
        schema = extractSchema;
      in
      devenv.lib.mkEval (
        args
        // {
          specialArgs = (args.specialArgs or { }) // {
            devenvSchema = schema;
          };
          modules = devenvIntegrationModules ++ (args.modules or [ ]);
        }
      );

    # Override mkConfig if it exists
    mkConfig =
      args:
      let
        schema = extractSchema;
      in
      devenv.lib.mkConfig (
        args
        // {
          specialArgs = (args.specialArgs or { }) // {
            devenvSchema = schema;
          };
        }
      );
  };

in
{
  # Re-export everything from devenv
  inherit (devenv) outputs modules templates;
  inherit (devenv) overlays packages;

  # Replace lib with wrapped version
  lib = wrappedLib;

  # Expose schema - LAZY: only evaluates when accessed
  schema = extractSchema;

  # Convenience: JSON-serializable schema for state.json
  schemaJson = builtins.toJSON extractSchema;

  # Expose the integration modules for manual import if needed
  inherit devenvIntegrationModules;
}
