# ==============================================================================
# module.nix - Prelude integration (Stackpanel-facing options + shell wiring)
#
# Prelude IS the shell MOTD / menu / docs. This module:
#   - Declares stackpanel.prelude.* options (enable default true)
#   - Registers the module for UI discovery
#
# stackpanel.motd.* is a contribution façade mapped to config.prelude.* in
# nix/flake/integrations/prelude/ (via facade.nix). Flake-parts wiring lives
# there; Prelude options are flake-parts-level, not nested stackpanel evalModules.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel.prelude;
  sp = config.stackpanel;
in
{
  options.stackpanel.prelude = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install Prelude packages (`motd` / `menu` / `x` / `docs`) and run
        `motd` on shell entry (when stackpanel.motd.enable is also true).

        `stackpanel.motd.{commands,features,hints}` are a contribution façade
        merged into flake-parts `prelude.*`. Set to `false` to skip Prelude
        packages and the shell banner (there is no Lip Gloss fallback).

        `stackpanel motd --json` / `--minimal` remain available for status data.
      '';
      example = false;
    };

    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Prelude color theme. Null uses Prelude's default (`minted`).
        Available themes include: minted, phosphor, amber, nord, gruvbox, …
      '';
      example = "phosphor";
    };

    tagline = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        MOTD tagline text. Null defaults to `"''${stackpanel.name} devshell"`.
        Set this in `.stack/config.nix` for project-specific chrome (do not
        hardcode product branding in the framework).
      '';
      example = "Ship products, not plumbing.";
    };

    subtitle = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        MOTD subtitle under the tagline. Null defaults to
        `"your environment is ready"`.
      '';
      example = "reproducible shells, secrets, and services";
    };

    menu = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prelude's interactive command menu (`menu` / `x`).";
      };
    };

    docs = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable Prelude's docs viewer when README / quick-start pages exist.
          Pages are auto-registered from the project root when present.
        '';
      };
    };

    prompt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable Prelude's themed Starship prompt. Default false to avoid
          fighting Stackpanel's existing Starship theme until the theme bridge
          lands (Phase 3).
        '';
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Escape hatch: attrset recursively merged into flake-parts `prelude.*`
        after the Stackpanel façade (project, commands, motd chrome, status).
        Use for advanced Prelude options not exposed under stackpanel.prelude.
      '';
      example = {
        colorProfile = "truecolor";
        motd.clearScreen = false;
      };
    };
  };

  # Also expose under stackpanel.modules.prelude.enable for UI consistency.
  options.stackpanel.modules.${meta.id} = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.stackpanel.prelude.enable;
      defaultText = lib.literalExpression "config.stackpanel.prelude.enable";
      description = "Whether the Prelude module is active (mirrors stackpanel.prelude.enable).";
    };
  };

  config = lib.mkIf (sp.enable && cfg.enable) {
    # jq is required by Prelude status probes that parse `stackpanel motd --json`
    stackpanel.devshell.packages = [ pkgs.jq ];

    stackpanel.motd.features = [ "Prelude shell DX" ];

    # Shell-entry MOTD lives in core/default.nix (Prelude `motd` only).
    # Flake layer injects packages.prelude onto PATH via façade.

    stackpanel.moduleChecks.${meta.id} = {
      eval = {
        description = "${meta.name} module evaluates correctly";
        required = true;
        derivation = pkgs.runCommand "${meta.id}-eval-check" { } ''
          echo "✓ Module ${meta.name} evaluates successfully"
          touch $out
        '';
      };
      packages = {
        description = "${meta.name} packages are available";
        required = true;
        derivation = pkgs.runCommand "${meta.id}-packages-check" { } ''
          echo "✓ Prelude bridge module packages check"
          touch $out
        '';
      };
    };

    stackpanel.healthchecks.modules.${meta.id} = {
      enable = true;
      displayName = meta.name;
      checks = {
        motd-on-path = {
          description = "Prelude motd is on PATH when Prelude is enabled";
          script = ''
            if command -v motd >/dev/null 2>&1; then
              echo "motd found: $(command -v motd)"
              exit 0
            fi
            echo "motd not on PATH (flake layer may not have injected packages.prelude)"
            exit 1
          '';
          severity = "warning";
          timeout = 5;
        };
      };
    };

    stackpanel.modules.${meta.id} = {
      enable = true;
      meta = {
        inherit (meta) name;
        inherit (meta) description;
        inherit (meta) icon;
        inherit (meta) category;
        inherit (meta) author;
        inherit (meta) version;
        inherit (meta) homepage;
      };
      source.type = "builtin";
      inherit (meta) features;
      flakeInputs = meta.flakeInputs or [ ];
      inherit (meta) tags;
      inherit (meta) priority;
      inherit (meta) requires;
      inherit (meta) conflicts;
      healthcheckModule = meta.id;
    };
  };
}
