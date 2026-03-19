# ==============================================================================
# vscode-nix.nix
#
# VS Code integration for Nix: recommended extensions and nixd settings.
# Provides nixd options so Stackpanel options are discoverable in editor.
#
# This generates nix.serverSettings for nixd with:
#   - stackpanel: Full stackpanel options (from flake output)
#   - sp-user: Submodule options for stackpanel.users
#   - sp-app: Submodule options for stackpanel.apps
#   - sp-command: Submodule options for stackpanel.commands
#   - sp-task: Submodule options for stackpanel.tasks
#
# For users: references stackpanel via FlakeHub URL
# For stackpanel development: uses local reference via .stackpanel-root
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}: let
  ideCfg = config.stackpanel.ide;
  zedCfg = ideCfg.zed;
  stackpanelCfg = config.stackpanel;
  libnixd = import ./lib/nixd.nix {inherit lib;};
  # Expression to get stackpanel options from the flake
  nixdValues = libnixd.mkValues {
    project = stackpanelCfg.project;
    github = stackpanelCfg.github;
    # Use the actual project root path (not ${workspace_root} — Zed does NOT
    # expand variables inside lsp.*.settings values). The nixd wrapper script
    # disables pure-eval so absolute paths work.
    root = stackpanelCfg.root;
  };

  # Helper to get submodule options
  # For stackpanel repo: use local evalModules
  # For external users: use flake-based expression
  mkSubOptionsExpr = optionPath:
    if nixdValues.isStackpanelRepo && nixdValues.hasValidLocalRoot
    then "${nixdValues.localStackpanelOptionsExpr}.${optionPath}.type.getSubOptions []"
    else "${nixdValues.flakeOptionsExpr}.${optionPath}.type.getSubOptions []";

  # Wrapper script for nixd that disables pure-eval.
  # nixd option expressions require importing nixpkgs and local module paths,
  # both of which are forbidden in pure evaluation mode.
  nixdWrapper = pkgs.writeShellScript "nixd-wrapper" ''
    export NIX_CONFIG="pure-eval = false''${NIX_CONFIG:+
    $NIX_CONFIG}"
    exec ${pkgs.nixd}/bin/nixd "$@"
  '';
in {
  config = lib.mkIf (ideCfg.enable && zedCfg.enable) {
    stackpanel.devshell.packages = [
      pkgs.nixd
      pkgs.nixfmt
    ];

    stackpanel.ide.zed.settings-modules = lib.mkAfter [
      {
        config = {
          # loads tools inside nix shell
          load_direnv = "shell_hook";
          lsp = {
            nixd = {
              binary = {
                "path" = "${nixdWrapper}";
              };
              initialization_options = {
                "formatting" = {
                  "command" = ["nixfmt"];
                };
              };
              settings = {
                "options" = {
                  # `config.*` option completion uses the "nixos" slot in nixd.
                  # For stackpanel development, point it at stackpanel's full options set.
                  "nixos" = {
                    "expr" = nixdValues.nixosOptionsExpr;
                  };
                  # Full stackpanel options (stackpanel.*)
                  "stackpanel" = {
                    "expr" = nixdValues.optionsExpr;
                  };
                  # Submodule options for common attrs
                  "sp-user" = {
                    "expr" = mkSubOptionsExpr "users";
                  };
                  "sp-app" = {
                    "expr" = mkSubOptionsExpr "apps";
                  };
                  "sp-task" = {
                    "expr" = mkSubOptionsExpr "tasks";
                  };
                };
              };
            };
            nil = {
              binary = {
                path = "${pkgs.nil}/bin/nil";
              };
              initialization_options = {
                "formatting" = {
                  "command" = ["alejandra"];
                };
              };
              settings = {
                "options" = {
                  "stackpanel" = {
                    "expr" = nixdValues.optionsExpr;
                  };
                };
                "nix" = {
                  "maxMemoryMB" = 8192;
                  "flake" = {
                    "autoEvalInputs" = true;
                    "nixpkgsInputName" = "nixpkgs";
                  };
                };
              };
            };
          };
        };
      }
    ];
  };
}
