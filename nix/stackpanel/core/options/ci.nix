# ==============================================================================
# ci.nix
#
# CI/CD configuration options - generate workflow files from Nix.
#
# Enables declarative CI/CD pipeline configuration that generates workflow
# files (e.g., GitHub Actions) from Nix definitions.
#
# Options:
#   - enable: Enable CI/CD generation
#   - github.enable: Enable GitHub Actions
#   - github.workflows: Raw workflow definitions (escape hatch)
#   - github.checks: Higher-level standard CI checks pattern
#
# Usage:
#   stackpanel.ci = {
#     enable = true;
#     github.checks = {
#       enable = true;
#       branches = ["main"];
#       commands = ["nix flake check" "nix build"];
#     };
#   };
# ==============================================================================
{lib,...}: {
  options.stackpanel.ci = {
    enable = lib.mkEnableOption "CI/CD generation";

    github = {
      enable = lib.mkEnableOption "GitHub Actions";

      # Escape hatch: raw workflow definitions
      workflows = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = {};
        description = "Workflow name -> workflow definition (raw)";
      };

      # Higher-level: common patterns
      checks = {
        enable = lib.mkEnableOption "standard CI checks workflow";
        branches = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["main"];
        };
        commands = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          example = ["nix flake check" "nix build"];
        };
      };
    };
  };
}