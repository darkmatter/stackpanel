# ==============================================================================
# checks.nix - Flake Check Options
#
# Defines the schema for module checks that run during `nix flake check`.
# These are build-time checks used in CI, separate from runtime health checks.
#
# Check Categories:
# - eval: Module evaluates without errors (required for certification)
# - packages: Required packages are available (required for certification)
# - config: Configuration generation works (recommended)
# - integration: Works with sample project (recommended)
# - lint: Code passes linting (optional)
# - custom: Module-specific checks (optional)
#
# Certification Requirements:
# For a module to be "certified", it must pass:
# 1. eval check - proves module evaluates
# 2. packages check - proves dependencies are available
# ==============================================================================
{ lib, config, pkgs, ... }:
let
  cfg = config.stackpanel;

  # ---------------------------------------------------------------------------
  # Check Category Schema
  # ---------------------------------------------------------------------------
  checkCategoryType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable description of what this check verifies";
      };

      required = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this check is required for module certification";
      };

      derivation = lib.mkOption {
        type = lib.types.package;
        description = "The derivation that runs this check (must succeed to pass)";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Timeout in seconds for this check";
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Module Check Schema
  # ---------------------------------------------------------------------------
  moduleCheckType = lib.types.submodule ({ name, ... }: {
    options = {
      # Required checks for certification
      eval = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Evaluation check - verifies the module evaluates without errors.
          Required for module certification.
        '';
      };

      packages = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Packages check - verifies required packages are available.
          Required for module certification.
        '';
      };

      # Recommended checks
      config = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Configuration check - verifies config generation works correctly.
          Recommended for modules that generate config files.
        '';
      };

      integration = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Integration check - verifies module works with a sample project.
          Recommended for complex modules.
        '';
      };

      # Optional checks
      lint = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Lint check - verifies the module's code passes linting.
          Optional.
        '';
      };

      custom = lib.mkOption {
        type = lib.types.attrsOf checkCategoryType;
        default = {};
        description = ''
          Custom module-specific checks.
          Use this for checks that don't fit the standard categories.
        '';
      };
    };
  });

  # ---------------------------------------------------------------------------
  # Computed Values
  # ---------------------------------------------------------------------------
  
  # Flatten all checks into a single attrset for flake output
  allChecks = lib.concatMapAttrs (moduleId: moduleChecks:
    let
      standardChecks = lib.filterAttrs (_: v: v != null) {
        "${moduleId}-eval" = moduleChecks.eval;
        "${moduleId}-packages" = moduleChecks.packages;
        "${moduleId}-config" = moduleChecks.config;
        "${moduleId}-integration" = moduleChecks.integration;
        "${moduleId}-lint" = moduleChecks.lint;
      };
      customChecks = lib.mapAttrs' 
        (name: check: lib.nameValuePair "${moduleId}-${name}" check) 
        moduleChecks.custom;
    in
    standardChecks // customChecks
  ) cfg.moduleChecks;

  # Extract just the derivations for flake checks output
  checkDerivations = lib.mapAttrs (_: check: check.derivation) allChecks;

  # Check certification status for each module
  certificationStatus = lib.mapAttrs (moduleId: moduleChecks:
    let
      hasEval = moduleChecks.eval != null;
      hasPackages = moduleChecks.packages != null;
      isCertified = hasEval && hasPackages;
      missingRequired = lib.optional (!hasEval) "eval" ++ lib.optional (!hasPackages) "packages";
    in {
      certified = isCertified;
      missing = missingRequired;
      checks = {
        eval = hasEval;
        packages = hasPackages;
        config = moduleChecks.config != null;
        integration = moduleChecks.integration != null;
        lint = moduleChecks.lint != null;
        customCount = builtins.length (lib.attrNames moduleChecks.custom);
      };
    }
  ) cfg.moduleChecks;

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  
  options.stackpanel.moduleChecks = lib.mkOption {
    type = lib.types.attrsOf moduleCheckType;
    default = {};
    description = ''
      Structured module checks organized by module ID.
      These are derivations that run during `nix flake check` and in CI.
      
      Each module can define checks in standard categories:
      - eval (required for certification)
      - packages (required for certification)
      - config (recommended)
      - integration (recommended)
      - lint (optional)
      - custom.* (module-specific)
      
      For simple flake checks, use stackpanel.checks instead.
      This option provides structured metadata for certification.
    '';
    example = lib.literalExpression ''
      {
        oxlint = {
          eval = {
            description = "OxLint module evaluates correctly";
            required = true;
            derivation = pkgs.runCommand "oxlint-eval" {} "touch $out";
          };
          packages = {
            description = "OxLint package is available";
            required = true;
            derivation = pkgs.runCommand "oxlint-packages" {
              nativeBuildInputs = [ pkgs.oxlint ];
            } "oxlint --version > $out";
          };
        };
      }
    '';
  };

  # Computed outputs
  options.stackpanel.moduleChecksFlattened = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    readOnly = true;
    default = checkDerivations;
    description = ''
      Flattened module check derivations for use in flake checks output.
      Keys are "<moduleId>-<category>" (e.g., "oxlint-eval").
    '';
  };

  options.stackpanel.moduleChecksCertification = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = certificationStatus;
    description = ''
      Certification status for each module.
      Shows which required checks are present/missing.
    '';
  };

  # ===========================================================================
  # Config
  # ===========================================================================
  
  # No config needed - modules set their own checks
}
