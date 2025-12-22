# GitHub Actions workflow generation
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.ci.github;

  # Proper YAML generation
  yaml = pkgs.formats.yaml {};
  toYaml = attrs: builtins.readFile (yaml.generate "workflow.yml" attrs);
in {
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

  config = lib.mkIf cfg.enable {
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

    # Generate workflow files using devenv's files option
    files =
      lib.mapAttrs' (name: workflow: {
        name = ".github/workflows/${name}.yml";
        value = { text = toYaml workflow; };
      })
      cfg.workflows;
  };
}
