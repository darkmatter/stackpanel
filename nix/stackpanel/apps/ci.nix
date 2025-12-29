# ==============================================================================
# ci.nix
#
# GitHub Actions CI/CD workflow generation module for devenv.
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
#   };
# ==============================================================================
{
  lib,
  config,
  options,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.ci.github;

  # Detect if we're in devenv context (files option is declared) vs standalone eval
  hasFilesOption = options ? files;

  # Proper YAML generation
  yaml = pkgs.formats.yaml {};
  toYaml = attrs: builtins.readFile (yaml.generate "workflow.yml" attrs);
in {


  config = lib.mkIf cfg.enable ({
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
          steps =
            [
              {uses = "actions/checkout@v4";}
              {uses = "cachix/install-nix-action@v30";}
            ]
            ++ map (cmd: {run = cmd;}) cfg.checks.commands;
        };
      };
    };
  } // lib.optionalAttrs hasFilesOption {
    # Generate workflow files using devenv's files option
    files =
      lib.mapAttrs' (name: workflow: {
        name = ".github/workflows/${name}.yml";
        value = { text = toYaml workflow; };
      })
      cfg.workflows;
  });
}
