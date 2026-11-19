# ==============================================================================
# vscode-nix.nix
#
# VS Code integration for Nix: recommended extensions and nixd settings.
# Provides nixd options so Stackpanel options are discoverable in editor.
#
# Keep the project's installed option tree and the SDK's raw mkModule options
# in separate nixd sets. The latter is not nested under `stackpanel.*`.
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
  stackpanelCfg = config.stackpanel;
  libnixd = import ./lib/nixd.nix {
    inherit pkgs lib;
    devenv = config._module.args.stackpanelDevenvNixd or null;
  };

  # Expression to get stackpanel options from the flake
  nixdValues = libnixd.mkValues {
    inherit (stackpanelCfg) project;
    inherit (stackpanelCfg) github;
    inherit (stackpanelCfg) root;
  };

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
          "nix.serverPath" = "${libnixd.launcher}";
          "nix.formatterPath" = "nixfmt";
          "nix.serverSettings" = {
            "nixd" = {
              "formatting" = {
                "command" = [ "nixfmt" ];
              };
              options = nixdValues.projectProvider // nixdValues.authorProvider;
            };
            "nil" = {
              "formatting" = {
                "command" = [ "alejandra" ];
              };
              options = nixdValues.projectProvider;
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
      }
    ];
  };
}
