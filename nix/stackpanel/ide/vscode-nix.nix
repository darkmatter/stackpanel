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
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  ideCfg = config.stackpanel.ide;
  vscodeCfg = ideCfg.vscode;

  # Use the flake's legacyPackages.stackpanelOptions for nixd
  # This works in any project that uses stackpanel, evaluated with --impure
  flakeOptionsExpr = "(builtins.getFlake (toString ./.)).legacyPackages.\${builtins.currentSystem}.stackpanelOptions";

  # Helper to get submodule options from the flake output
  mkSubOptionsExpr = optionPath: "${flakeOptionsExpr}.${optionPath}.type.getSubOptions []";
in
{
  config = lib.mkIf (ideCfg.enable && vscodeCfg.enable) {
    stackpanel.devshell.packages = [
      pkgs.nixd
      pkgs.nixfmt
    ];

    stackpanel.ide.vscode.extensions = lib.mkAfter [
      "jnoortheen.nix-ide"
    ];

    stackpanel.ide.vscode.settings-modules = lib.mkAfter [
      {
        config = {
          "[nix]" = {
            "editor.defaultFormatter" = "jnoortheen.nix-ide";
          };
          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "nixd";
          "nix.formatterPath" = "nixfmt";
          "nix.serverSettings" = {
            "nixd" = {
              "formatting" = {
                "command" = [ "nixfmt" ];
              };
              "options" = {
                # Disable default nixos options (not relevant for stackpanel projects)
                "nixos" = {
                  "expr" = "null";
                };
                # Full stackpanel options (from flake output)
                "stackpanel" = {
                  "expr" = flakeOptionsExpr;
                };
                # Submodule options for common attrs
                "sp-user" = {
                  "expr" = mkSubOptionsExpr "users";
                };
                "sp-app" = {
                  "expr" = mkSubOptionsExpr "apps";
                };
                "sp-command" = {
                  "expr" = mkSubOptionsExpr "commands";
                };
                "sp-task" = {
                  "expr" = mkSubOptionsExpr "tasks";
                };
              };
            };
          };
        };
      }
    ];
  };
}
