# ==============================================================================
# Zed integration for Nix project and raw mkModule option completion.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  ideCfg = config.stackpanel.ide;
  zedCfg = ideCfg.zed;
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
  config = lib.mkIf (ideCfg.enable && zedCfg.enable) {
    stackpanel.devshell.packages = [
      pkgs.nixd
      pkgs.nixfmt
    ];

    stackpanel.ide.zed.settings-modules = lib.mkAfter [
      {
        config = {
          languages.Nix.language_servers = [
            "nixd"
            "!nil"
          ];
          lsp = {
            nixd = {
              binary = {
                path = "${libnixd.launcher}";
              };
              initialization_options = {
                "formatting" = {
                  "command" = [ "nixfmt" ];
                };
              };
              settings = {
                options = nixdValues.zedNixosProvider // nixdValues.projectProvider // nixdValues.authorProvider;
              };
            };
            nil = {
              binary = {
                path = "${pkgs.nil}/bin/nil";
              };
              initialization_options = {
                "formatting" = {
                  "command" = [ "nixfmt" ];
                };
              };
              settings = {
                options = nixdValues.projectProvider;
                "nix" = {
                  # "maxMemoryMB" = 8192;
                  "flake" = {
                    "autoEvalInputs" = false;
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
