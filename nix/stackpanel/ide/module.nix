{
  lib,
  pkgs,
  config,
  ...
}:
let
  vscodeCfg = config.stackpanel.ide.vscode;
  zedCfg = config.stackpanel.ide.zed;

  # VS Code settings evaluation
  vscodeSettingsEval = lib.evalModules {
    modules = [
      {
        _module.freeformType = lib.types.attrsOf lib.types.anything;
      }
    ]
    ++ vscodeCfg.settings-modules;
    specialArgs = {
      inherit lib;
      inherit pkgs;
      stackpanelConfig = config.stackpanel;
    };
  };

  vscodeSettingsFromModules = vscodeSettingsEval.config;

  # Zed settings evaluation
  zedSettingsEval = lib.evalModules {
    modules = [
      {
        _module.freeformType = lib.types.attrsOf lib.types.anything;
      }
    ]
    ++ zedCfg.settings-modules;
    specialArgs = {
      inherit lib;
      inherit pkgs;
      stackpanelConfig = config.stackpanel;
    };
  };

  zedSettingsFromModules = zedSettingsEval.config;
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

  options.stackpanel.ide.zed.settings-modules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Modules that contribute Zed settings.

      These modules are merged into `stackpanel.ide.zed.settings` so their contents
      end up in the generated Zed settings.json.
    '';
    example = [
      {
        config = {
          lsp = {
            nixd = {
              settings = {
                diagnostic = {
                  suppress = [ "sema-extra-with" ];
                };
              };
            };
          };
        };
      }
    ];
  };

  config.stackpanel.ide.vscode.settings = lib.mkDefault vscodeSettingsFromModules;
  config.stackpanel.ide.zed.settings = lib.mkDefault zedSettingsFromModules;
}
