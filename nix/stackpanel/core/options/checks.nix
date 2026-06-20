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
{
  lib,
  config,
  ...
}:
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
        example = "Module evaluates with default config.";
      };

      required = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this check is required for module certification";
        example = true;
      };

      derivation = lib.mkOption {
        type = lib.types.package;
        description = "The derivation that runs this check (must succeed to pass)";
        example = lib.literalExpression ''pkgs.runCommand "module-eval" {} "touch $out"'';
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Maximum number of seconds this flake check may run before timing out.";
        example = 120;
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Module Check Schema
  # ---------------------------------------------------------------------------
  moduleCheckType = lib.types.submodule (_: {
    options = {
      # Required checks for certification
      eval = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Evaluation check - verifies the module evaluates without errors.
          Required for module certification.
        '';
        example = lib.literalExpression ''
          {
            description = "Verify the SST module evaluates without errors";
            required = true;
            derivation = pkgs.runCommand "sst-eval" {} "touch $out";
          }
        '';
      };

      packages = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Packages check - verifies required packages are available.
          Required for module certification.
        '';
        example = lib.literalExpression ''
          {
            description = "Verify required SST packages are available";
            required = true;
            derivation = pkgs.runCommand "sst-packages" { nativeBuildInputs = [ pkgs.nodejs ]; } "node --version > $out";
          }
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
        example = lib.literalExpression ''
          {
            description = "Verify generated configuration is valid JSON";
            derivation = pkgs.runCommand "config-json" { nativeBuildInputs = [ pkgs.jq ]; } "jq . ''${configFile} > $out";
          }
        '';
      };

      integration = lib.mkOption {
        type = lib.types.nullOr checkCategoryType;
        default = null;
        description = ''
          Integration check - verifies module works with a sample project.
          Recommended for complex modules.
        '';
        example = lib.literalExpression ''
          {
            description = "Template project builds with this module enabled";
            timeout = 600;
            derivation = pkgs.runCommand "module-integration" {} "touch $out";
          }
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
        example = lib.literalExpression ''
          {
            description = "Verify Nix sources pass statix linting";
            derivation = pkgs.runCommand "module-lint" { nativeBuildInputs = [ pkgs.statix ]; } "statix check ''${src} && touch $out";
          }
        '';
      };

      custom = lib.mkOption {
        type = lib.types.attrsOf checkCategoryType;
        default = { };
        description = ''
          Custom module-specific checks.
          Use this for checks that don't fit the standard categories.
        '';
        example = lib.literalExpression ''
          {
            smoke = {
            description = "Smoke-test the generated command wrapper";
              derivation = pkgs.runCommand "module-smoke" {} "touch $out";
            };
          }
        '';
      };
    };
  });

  # ---------------------------------------------------------------------------
  # Computed Values
  # ---------------------------------------------------------------------------

  # Flatten all checks into a single attrset for flake output
  allChecks = lib.concatMapAttrs (
    moduleId: moduleChecks:
    let
      standardChecks = lib.filterAttrs (_: v: v != null) {
        "${moduleId}-eval" = moduleChecks.eval;
        "${moduleId}-packages" = moduleChecks.packages;
        "${moduleId}-config" = moduleChecks.config;
        "${moduleId}-integration" = moduleChecks.integration;
        "${moduleId}-lint" = moduleChecks.lint;
      };
      customChecks = lib.mapAttrs' (
        name: check: lib.nameValuePair "${moduleId}-${name}" check
      ) moduleChecks.custom;
    in
    standardChecks // customChecks
  ) cfg.moduleChecks;

  # Extract just the derivations for flake checks output
  checkDerivations = lib.mapAttrs (_: check: check.derivation) allChecks;

  # Check certification status for each module
  certificationStatus = lib.mapAttrs (
    _moduleId: moduleChecks:
    let
      hasEval = moduleChecks.eval != null;
      hasPackages = moduleChecks.packages != null;
      isCertified = hasEval && hasPackages;
      missingRequired = lib.optional (!hasEval) "eval" ++ lib.optional (!hasPackages) "packages";
    in
    {
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
    default = { };
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
            description = "Verify the OxLint module evaluates correctly";
            required = true;
            derivation = pkgs.runCommand "oxlint-eval" {} "touch $out";
          };
          packages = {
            description = "Verify the OxLint package is available";
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
    example = lib.literalExpression ''
      {
        oxlint-eval = pkgs.runCommand "oxlint-eval" {} "touch $out";
        oxlint-packages = pkgs.runCommand "oxlint-packages" {} "touch $out";
      }
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
    example = lib.literalExpression ''
      {
        oxlint = {
          certified = true;
          missing = [ ];
          checks = { eval = true; packages = true; config = false; integration = false; lint = false; customCount = 0; };
        };
      }
    '';
  };

  # ===========================================================================
  # Config
  # ===========================================================================

  # No config needed - modules set their own checks
}
