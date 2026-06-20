# ==============================================================================
# ci.nix
#
# GitHub Actions CI/CD workflow generation module.
#
# This module provides declarative configuration for generating GitHub Actions
# workflow files. Workflows are defined using Nix and automatically converted
# to YAML format in .github/workflows/.
#
# Usage:
#   stackpanel.ci.github = {
#     enable = true;
#     checks = {
#       enable = true;
#       branches = ["main"];
#       commands = ["nix flake check"];
#     };
#     workflows.release = {
#       name = "Release";
#       on.push.tags = ["v*"];
#       jobs.release = {
#         runs-on = "ubuntu-latest";
#         steps = [
#           { uses = "actions/checkout@v4"; }
#           { run = "nix build"; }
#         ];
#       };
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  options,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.ci.github;

  # Detect if we're in devenv context (files option is declared) vs standalone eval
  hasFilesOption = options ? files;

  # Proper YAML generation
  yaml = pkgs.formats.yaml { };
  toYaml = attrs: builtins.readFile (yaml.generate "workflow.yml" attrs);
in
{
  # ── Options (colocated from core/options/ci.nix) ─────────────────────────────
  options.stackpanel.ci = {
    enable = lib.mkEnableOption "CI/CD workflow file generation";

    github = {
      enable = lib.mkEnableOption "GitHub Actions workflow generation";

      # Escape hatch: raw workflow definitions
      workflows = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = ''
          Raw GitHub Actions workflow definitions keyed by output file name.

          Each attrset is serialized to `.github/workflows/<name>.yml` when the
          hosting module exposes a `files` option. Use this for custom workflows
          such as release, deploy, preview, or security scans. The attrset shape
          should match GitHub Actions YAML.
        '';
        example = lib.literalExpression ''
          {
            release = {
              name = "Release";
              on.push.tags = [ "v*" ];
              jobs.release = {
                runs-on = "ubuntu-latest";
                steps = [
                  { uses = "actions/checkout@v4"; }
                  { uses = "cachix/install-nix-action@v30"; }
                  { run = "nix build"; }
                ];
              };
            };

            deploy-preview = {
              name = "Deploy preview";
              on.pull_request.branches = [ "main" ];
              jobs.preview = {
                runs-on = "ubuntu-latest";
                steps = [
                  { uses = "actions/checkout@v4"; }
                  { run = "bun run deploy:preview"; }
                ];
              };
            };
          }
        '';
      };

      # Higher-level: common patterns
      checks = {
        enable = lib.mkEnableOption "standard CI checks workflow";
        branches = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "main" ];
          description = ''
            Branches that trigger the generated checks workflow on push and pull
            request events.
          '';
          example = [
            "main"
            "release/*"
          ];
        };
        commands = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Shell commands run after checkout and Nix installation in the
            generated `ci.yml` checks job. Commands run in order on Ubuntu.
          '';
          example = [
            "nix flake check"
            "nix build"
            "bun run check-types"
          ];
        };
      };
    };
  };

  # ── Config ───────────────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable (
    {
      # Build workflows from high-level options
      stackpanel.ci.github.workflows = lib.mkIf cfg.checks.enable {
        ci = {
          name = "CI";
          on = {
            push.branches = cfg.checks.branches;
            pull_request.branches = cfg.checks.branches;
          };
          jobs.check = {
            runs-on = "ubuntu-latest";
            steps = [
              { uses = "actions/checkout@v4"; }
              { uses = "cachix/install-nix-action@v30"; }
            ]
            ++ map (cmd: { run = cmd; }) cfg.checks.commands;
          };
        };
      };
    }
    // lib.optionalAttrs hasFilesOption {
      # Generate workflow files using devenv's files option
      files = lib.mapAttrs' (name: workflow: {
        name = ".github/workflows/${name}.yml";
        value = {
          text = toYaml workflow;
        };
      }) cfg.workflows;
    }
  );
}
