# ==============================================================================
# recommended.nix
#
# Recommended settings module for devenv integration. Provides opinionated,
# battle-tested defaults for formatters, linters, and IDE configuration.
#
# Usage:
#   stackpanel.devenv.recommended.enable = true;        # Enable all
#   stackpanel.devenv.recommended.formatters.enable = true;  # Just formatters
#
# Formatter defaults (when enabled):
#   - alejandra: Nix code formatter
#   - shellcheck: Shell script linter
#   - ruff-format/ruff-check: Python formatting (when Python enabled)
#   - mdformat: Markdown formatter with numbered lists
#
# Only active in devenv context (detects enterShell option).
# ==============================================================================
{ pkgs, lib, config, options, ... }: let
  cfg = config.stackpanel.devenv.recommended;
  ideCfg = config.stackpanel.ide;
  stackpanelCfg = config.stackpanel;

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

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
  config = lib.mkMerge ([
    (lib.mkIf (config.stackpanel.enable && cfg.enable) {
      # Base recommended settings when enabled
    })

    (lib.mkIf (config.stackpanel.enable && (cfg.ide.enable or false)) {
      # Recommended IDE settings
    })
  ] ++ lib.optionals isDevenv [
    # Recommended formatter settings (only in devenv context)
    (lib.mkIf (config.stackpanel.enable && (cfg.formatters.enable or false)) {
        treefmt.enable = true;
        treefmt.config.programs.alejandra.enable = true;
        treefmt.config.programs.shellcheck.enable = true;
        treefmt.config.programs.ruff-format.enable = lib.mkIf (config.languages.python.enable or false) true;
        treefmt.config.programs.ruff-check.enable = lib.mkIf (config.languages.python.enable or false) true;
        treefmt.config.programs.mdformat.enable = true;
        treefmt.config.programs.mdformat.settings.number = true;
        treefmt.config.settings.formatter.shellcheck.options = ["-C" "auto"];
    })
  ]);
}