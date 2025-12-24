# Recommended settings module
#
# This module configures devenv with recommended, opinionated settings when
# stackpanel.devenv.recommended.enable is set to true.
# To enable recommended settings only on specific modules (such as formatters),
# set stackpanel.devenv.recommended.[module].enable = true.
{ pkgs, lib, config, ... }: let
  cfg = config.stackpanel.devenv.recommended;
  ideCfg = config.stackpanel.ide;
  stackpanelCfg = config.stackpanel;
  ideLib = import ../ide/lib.nix { inherit pkgs lib config; };
in {
  options.stackpanel.devenv.recommended = {
    enable = lib.mkEnableOption "Enable recommended stackpanel.devenv settings" // {
      description = "When enabled, applies recommended settings for stackpanel.devenv integration.";
    };
    formatters = {
      enable = lib.mkEnableOption "Enable recommended formatter settings" // {
        description = "When enabled, applies recommended settings for code formatters in the dev environment.";
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf (config.stackpanel.enable && cfg.enable) {
      # Base recommended settings when enabled
    })

    (lib.mkIf (config.stackpanel.enable && cfg.formatters.enable or false) {
      # Recommended formatter settings
        treefmt.enable = true;
        treefmt.config.programs.alejandra.enable = true;
        treefmt.config.programs.shellcheck.enable = true;
        treefmt.config.programs.ruff-format.enable = lib.mkIf config.languages.python.enable true;
        treefmt.config.programs.ruff-check.enable = lib.mkIf config.languages.python.enable true;
        treefmt.config.programs.mdformat.enable = true;
        treefmt.config.programs.mdformat.settings.number = true;
        treefmt.config.settings.formatter.shellcheck.options = ["-C" "auto"];
    })

    (lib.mkIf (config.stackpanel.enable && cfg.ide.enable or false) {
      # Recommended IDE settings
    })
  ];
}