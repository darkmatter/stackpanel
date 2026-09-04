# ==============================================================================
# checks.nix - Deprecated build-check sugar
#
# `stackpanel.moduleChecks.<module>` is the pre-`doctor` way to declare
# build-time checks for `nix flake check`. It still works: every category
# (eval, packages, config, integration, lint, custom.<name>) is written into
# `stackpanel.doctor.<module>.<name>` with `scope = "build"`.
#
# Prefer declaring checks directly:
#
#   stackpanel.doctor.oxlint.eval = {
#     scope = "build";
#     required = true;
#     derivation = pkgs.runCommand "oxlint-eval" { } "touch $out";
#   };
#
# The computed outputs (`moduleChecksFlattened`, `moduleChecksCertification`)
# are read-only views defined in doctor.nix and are byte-identical to what this
# option produced on its own.
#
# Certification: a module is certified when it declares both an `eval` and a
# `packages` build check.
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
  # Sugar: lower each legacy module entry onto doctor build-scope checks
  # ---------------------------------------------------------------------------
  standardCategories =
    mc:
    lib.filterAttrs (_: v: v != null) {
      inherit (mc)
        eval
        packages
        config
        integration
        lint
        ;
    };

  toDoctorCheck = c: {
    scope = "build";
    inherit (c)
      description
      required
      derivation
      timeout
      ;
  };
in
{
  options.stackpanel.moduleChecks = lib.mkOption {
    type = lib.types.attrsOf moduleCheckType;
    default = { };
    description = ''
      Deprecated: declare build checks under `stackpanel.doctor.<module>.<name>`
      with `scope = "build"` instead.

      Structured module checks organized by module ID. These are derivations
      that run during `nix flake check` and in CI. Each category
      (eval, packages, config, integration, lint, custom.*) becomes
      `stackpanel.doctor.<module>.<category>`.

      For simple flake checks, use stackpanel.checks instead.
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

  config.stackpanel.doctor = lib.mapAttrs (
    _: mc: lib.mapAttrs (_: toDoctorCheck) (standardCategories mc // mc.custom)
  ) cfg.moduleChecks;
}
