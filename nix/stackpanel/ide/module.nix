{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.stackpanel.ide.vscode;

  settingsEval = lib.evalModules {
    modules = [
      {
        _module.freeformType = lib.types.attrsOf lib.types.anything;
      }
    ]
    ++ cfg.settings-modules;
    specialArgs = {
      inherit lib;
      inherit pkgs;
      stackpanelConfig = config.stackpanel;
    };
  };

  settingsFromModules = settingsEval.config;
in
{
  options.stackpanel.ide.vscode.settings-modules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Modules that contribute VS Code settings.

      These modules are merged into `stackpanel.ide.vscode.settings` so their
      contents end up in the generated VS Code settings.json.
    '';
    example = [
      {
        config = {
          "[nix]" = {
            "editor.defaultFormatter" = "jnoortheen.nix-ide";
          };
        };
      }
    ];
  };

  config.stackpanel.ide.vscode.settings = lib.mkDefault settingsFromModules;
}
