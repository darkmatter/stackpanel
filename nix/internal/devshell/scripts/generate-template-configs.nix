# ==============================================================================
# generate-template-configs.nix  (INTERNAL — stackpanel development only)
#
# This is the *single* place that turns the live option schema into the
# checked-in starter configs that users eventually receive.
#
# Flow:
#   mkOptionsDoc + nixosOptionsDoc
#     -> options.json
#     -> stack config generate --template-config --options-json ...
#     -> written to nix/flake/templates/{default,minimal}/.stack/config.nix
#     -> also synced to the embed copies the CLI binary uses at runtime
#     -> committed
#
# Those files under nix/flake/templates are user-facing (they are what
# `nix flake init -t` and `stack init` and `stack config generate` all surface).
#
# This script must be run manually by stackpanel maintainers when the option
# schema changes. If it is not run, `stack config generate` (and new inits)
# will serve a stale view of the options → drift.
#
# We treat this as an explicit manual step (rather than auto during nix build)
# because the outputs are checked into source control to keep `nix flake init -t`
# and the init-equivalence test simple and hermetic.
#
# Placed under nix/internal to make the internal/maintainer nature obvious.
# Nothing under nix/internal is part of the public stackpanel API or shipped
# behavior for end users.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;

  generateTemplateConfigsScript = pkgs.writeShellScriptBin "stackpanel-generate-template-configs" ''
    set -euo pipefail

    ROOT_DIR="''${STACKPANEL_ROOT:-$(pwd)}"
    TEMPLATE_ROOT="$ROOT_DIR/nix/flake/templates"

    echo "Generating template config.nix files from option metadata..."
    echo "  Templates: default, minimal"
    echo "  Template root: $TEMPLATE_ROOT"

    echo "  Building options documentation..."
    OPTIONS_JSON=$(nix build --impure --no-link --print-out-paths \
      --expr 'let
        pkgs = import <nixpkgs> {};
        lib = pkgs.lib;
        mkOptionsDoc = import '"$ROOT_DIR"'/nix/stackpanel/lib/options-doc.nix { inherit pkgs lib; };
      in (mkOptionsDoc {}).optionsJSON'
    )
    OPTIONS_JSON_FILE="$OPTIONS_JSON/share/doc/nixos/options.json"

    if [ ! -f "$OPTIONS_JSON_FILE" ]; then
      echo "Error: Failed to generate options JSON"
      exit 1
    fi

    echo "  Options JSON: $OPTIONS_JSON_FILE"

    echo "  Building stackpanel CLI..."
    CLI=$(nix build --no-link --print-out-paths "$ROOT_DIR#stackpanel")
    STACKPANEL_BIN="$CLI/bin/stackpanel"

    if [ ! -x "$STACKPANEL_BIN" ]; then
      echo "Error: Failed to build stackpanel CLI"
      exit 1
    fi

    generate_template() {
      local template="$1"
      local mode="$2"
      local output_path="$TEMPLATE_ROOT/$template/.stack/config.nix"

      mkdir -p "$(dirname "$output_path")"

      echo "  Generating $template -> $output_path"
      if [ "$mode" = "minimal" ]; then
        "$STACKPANEL_BIN" config generate \
          --options-json "$OPTIONS_JSON_FILE" \
          --output "$output_path" \
          --template-config \
          --no-comments
      else
        "$STACKPANEL_BIN" config generate \
          --options-json "$OPTIONS_JSON_FILE" \
          --output "$output_path" \
          --template-config
      fi
    }

    generate_template default annotated
    generate_template minimal minimal

    echo "  Formatting generated configs..."
    ${pkgs.nixfmt-rfc-style}/bin/nixfmt \
      "$TEMPLATE_ROOT/default/.stack/config.nix" \
      "$TEMPLATE_ROOT/minimal/.stack/config.nix"

    # Sync the embed copies consumed by the Go binary via //go:embed.
    # The canonical files are the ones under nix/flake/templates.
    # Go embed forbids ".." paths, so we keep byte-copies inside the Go package.
    echo "  Syncing embed copies..."
    EMBED_DIR="$ROOT_DIR/apps/stackpanel-go/cmd/cli/template_configs"
    mkdir -p "$EMBED_DIR"
    cp "$TEMPLATE_ROOT/default/.stack/config.nix" "$EMBED_DIR/default.nix"
    cp "$TEMPLATE_ROOT/minimal/.stack/config.nix" "$EMBED_DIR/minimal.nix"
    ${pkgs.nixfmt-rfc-style}/bin/nixfmt \
      "$EMBED_DIR/default.nix" \
      "$EMBED_DIR/minimal.nix"

    echo ""
    echo "Generated (and committed) starter templates:"
    echo "  nix/flake/templates/default/.stack/config.nix"
    echo "  nix/flake/templates/minimal/.stack/config.nix"
    echo "  (embed copies under apps/stackpanel-go/cmd/cli/template_configs/)"
    echo ""
    echo "Remember to commit the result and push. Otherwise users running"
    echo "'stack config generate' or 'nix flake init -t' will see stale options."
  '';
in
{
  config = lib.mkIf cfg.enable {
    stackpanel.scripts.generate-template-configs = {
      description = "INTERNAL: Regenerate the checked-in starter configs + embed copies from the option schema";
      exec = ''
        ${generateTemplateConfigsScript}/bin/stackpanel-generate-template-configs "$@"
      '';
      timeout = 1800;
    };

    # We keep the MOTD hint inside the stackpanel repo so contributors know
    # how to refresh user-facing starters when they touch options.
    stackpanel.motd.hints = [
      "Run 'generate-template-configs' after option schema changes (maintainers)"
    ];
  };
}
