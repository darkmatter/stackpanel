# ==============================================================================
# vscode-nix.nix
#
# VS Code integration for Nix: recommended extensions and nixd settings.
# Provides nixd options so Stackpanel options are discoverable in editor.
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
  optionsExpr = ''
    let
      system = builtins.currentSystem;
      pkgs = import <nixpkgs> { inherit system; };
      lib = pkgs.lib;
    in
      (lib.evalModules {
        modules = [
          ./nix/stackpanel/core/options
          { _module.args = { inherit pkgs lib; }; }
        ];
      }).options
  '';
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
          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "nixd";
          "nix.formatterPath" = "nixfmt";
          "nix.serverSettings" = {
            "nixd" = {
              "formatting" = {
                "command" = [ "nixfmt" ];
              };
              "options" = {
                "stackpanel" = {
                  "expr" = optionsExpr;
                };
              };
            };
          };
        };
      }
    ];
  };
}
