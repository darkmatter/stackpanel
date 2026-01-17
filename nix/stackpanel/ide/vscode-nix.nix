# ==============================================================================
# vscode-nix.nix
#
# VS Code integration for Nix: recommended extensions and nixd settings.
# Provides nixd options so Stackpanel options are discoverable in editor.
#
# This generates nix.serverSettings for nixd with:
#   - stackpanel: Full stackpanel options
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

  # Shared eval modules expression
  evalModulesExpr = "lib.evalModules { modules = [ ./nix/stackpanel/core/options { _module.args = { inherit pkgs lib; }; } ]; }";

  # Main stackpanel options expression
  stackpanelExpr = "let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in (${evalModulesExpr}).options.stackpanel";

  # Helper to generate getSubOptions expression for a submodule option
  # Uses same let binding pattern as user's config for consistency
  mkSubOptionsExpr = optionPath: "let pkgs = import <nixpkgs> {}; lib = pkgs.lib; eval = ${evalModulesExpr}; in eval.options.stackpanel.${optionPath}.type.getSubOptions []";
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
                # Full stackpanel options
                "stackpanel" = {
                  "expr" = stackpanelExpr;
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
