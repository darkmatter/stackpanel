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
# For stackpanel development: uses local reference via STACKPANEL_ROOT
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  ideCfg = config.stackpanel.ide;
  vscodeCfg = ideCfg.zed;
  stackpanelCfg = config.stackpanel;
  libnixd = import ./lib/nixd.nix { inherit lib; };
  # Expression to get stackpanel options from the flake
  nixdValues = libnixd.mkValues {
    project = stackpanelCfg.project;
    github = stackpanelCfg.github;
    root = stackpanelCfg.root;
  };

  # Helper to get submodule options from the flake output
  mkSubOptionsExpr = optionPath: "${nixdValues.flakeOptionsExpr}.${optionPath}.type.getSubOptions []";
in
{
  config = lib.mkIf (ideCfg.enable && vscodeCfg.enable) {
    stackpanel.devshell.packages = [
      pkgs.nixd
      pkgs.nixfmt
    ];

    stackpanel.ide.zed.settings-modules = lib.mkAfter [
      {
        config = {
          "lsp.nixd" = {
            "formatting" = {
              "command" = [ "nixfmt" ];
            };
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
          "lsp.nil" = {
            "formatting" = {
              "command" = [ "alejandra" ];
            };
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
      }
    ];
  };
}
