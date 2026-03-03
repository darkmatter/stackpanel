# ==============================================================================
# catalog.nix - Bun Workspace Catalog Management
#
# Collects NPM dependency declarations from Nix modules and generates a
# catalog manifest that the CLI can sync into the root package.json.
#
# Problem:
#   Modules declare dependencies as `"@aws-sdk/client-ecr" = "catalog:";` in
#   workspace package.json files, but the root package.json catalog (which maps
#   package names to actual version constraints) is maintained by hand. When a
#   module adds a new catalog reference, `bun install` fails because the
#   catalog entry doesn't exist.
#
# Solution:
#   Modules declare dependencies with real version constraints via
#   `stackpanel.bun.catalog`. This module:
#     1. Merges all declarations into a single catalog
#     2. Generates a manifest at .stackpanel/state/catalog.json
#     3. The CLI reads the manifest and syncs missing entries into root package.json
#     4. Computes a content hash for staleness detection (bun.lock / bun.nix)
#     5. Exposes a healthcheck that warns when the catalog or lockfiles are stale
#
# Usage (from any module):
#   stackpanel.bun.catalog = {
#     "@aws-sdk/client-ecr" = "^3.953.0";
#     "@aws-sdk/client-elastic-load-balancing-v2" = "^3.953.0";
#     "@tanstack/react-router" = "^1.143.6";
#   };
#
# The generated manifest (.stackpanel/state/catalog.json) contains:
#   { "catalog": { "@aws-sdk/client-ecr": "^3.953.0", ... }, "hash": "..." }
#
# The CLI (or shell hook) reads this manifest and:
#   1. Compares it against the root package.json workspaces.catalog
#   2. Reports missing or outdated entries
#   3. Offers to sync them automatically (`sp catalog sync`)
#
# Staleness detection:
#   The catalog hash is exported as STACKPANEL_CATALOG_HASH. A healthcheck
#   compares the Nix-computed catalog against what's in the root package.json.
#   If they differ, the MOTD warns that `sp catalog sync` is needed.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  sp = config.stackpanel;
  catalogCfg = sp.bun.catalog;
  hasCatalog = catalogCfg != { };

  # Compute a deterministic hash of all catalog entries for staleness detection.
  # Sorted by key so the hash is stable regardless of module evaluation order.
  sortedKeys = builtins.sort builtins.lessThan (builtins.attrNames catalogCfg);
  catalogFingerprint = builtins.concatStringsSep "\n" (
    map (k: "${k}=${catalogCfg.${k}}") sortedKeys
  );
  catalogHash = builtins.hashString "sha256" catalogFingerprint;

  # State directory for writing the hash file
  stateDir = sp.dirs.state or ".stack/profile";

in
{
  # ============================================================================
  # Options
  # ============================================================================
  options.stackpanel.bun.catalog = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      Bun workspace catalog entries.

      Maps NPM package names to version constraints. These are merged from
      all modules and written to the root package.json under
      `workspaces.catalog`.

      Modules that need an NPM dependency should declare it here with the
      real version, then reference it as `"catalog:"` in their workspace
      package.json dependencies.

      Multiple modules can declare the same package. If versions conflict,
      the Nix module system's standard merge/priority rules apply — use
      `lib.mkForce` or `lib.mkOverride` to resolve conflicts explicitly.

      Example:
        stackpanel.bun.catalog = {
          "@aws-sdk/client-ecr" = "^3.953.0";
          "alchemy" = "^0.81.2";
          "react" = "19.2.4";
        };
    '';
    example = lib.literalExpression ''
      {
        "@aws-sdk/client-ecr" = "^3.953.0";
        "react" = "19.2.4";
        "zod" = "^4.1.13";
      }
    '';
  };

  options.stackpanel.bun.catalogHash = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = if hasCatalog then catalogHash else "";
    description = ''
      SHA-256 hash of the resolved catalog contents.

      Used for staleness detection: if this hash differs from the one
      recorded in .stackpanel/state/catalog-hash, the lockfiles (bun.lock
      and bun.nix) need to be regenerated.

      This is a read-only computed value.
    '';
  };

  # ============================================================================
  # Config
  # ============================================================================
  config = lib.mkIf (sp.enable && hasCatalog) {

    # --------------------------------------------------------------------------
    # Generate catalog manifest to state dir
    #
    # Contains the full set of module-declared catalog entries and a content
    # hash. The CLI reads this manifest and syncs entries into the root
    # package.json (which is hand-maintained and cannot be fully generated).
    # --------------------------------------------------------------------------
    stackpanel.files.entries."${stateDir}/catalog.json" = {
      type = "json";
      jsonValue = {
        catalog = catalogCfg;
        hash = catalogHash;
      };
      source = "bun-catalog";
      description = "Workspace catalog manifest (module-declared NPM dependency versions)";
    };

    # --------------------------------------------------------------------------
    # Export catalog hash as environment variable
    #
    # Available to shell hooks, healthchecks, and the MOTD for fast comparison
    # without reading the state file.
    # --------------------------------------------------------------------------
    stackpanel.devshell.env = {
      STACKPANEL_CATALOG_HASH = catalogHash;
    };

    # --------------------------------------------------------------------------
    # Healthcheck: detect catalog entries missing from root package.json
    #
    # Reads the Nix-generated catalog manifest and compares it against the
    # root package.json workspaces.catalog. Reports any missing or mismatched
    # entries so the user can run `sp catalog sync`.
    # --------------------------------------------------------------------------
    stackpanel.healthchecks.modules.bun-catalog = {
      enable = true;
      checks = {
        catalog-in-sync = {
          name = "Workspace catalog in sync";
          description = "Check if root package.json catalog has all module-declared entries";
          type = "script";
          severity = "warning";
          script = ''
            MANIFEST="$STACKPANEL_ROOT/${stateDir}/catalog.json"
            ROOT_PKG="$STACKPANEL_ROOT/package.json"

            if [ ! -f "$MANIFEST" ]; then
              echo "No catalog manifest — regenerate shell"
              exit 1
            fi
            if [ ! -f "$ROOT_PKG" ]; then
              echo "No root package.json found"
              exit 1
            fi

            # Extract catalog from manifest and root package.json
            MANIFEST_CATALOG=$(${lib.getExe pkgs.jq} -S '.catalog // {}' "$MANIFEST")
            ROOT_CATALOG=$(${lib.getExe pkgs.jq} -S '.workspaces.catalog // {}' "$ROOT_PKG")

            # Find keys in manifest that are missing from root catalog
            MISSING=$(${lib.getExe pkgs.jq} -n \
              --argjson manifest "$MANIFEST_CATALOG" \
              --argjson root "$ROOT_CATALOG" \
              '[$manifest | keys[] | select(. as $k | $root | has($k) | not)]')

            COUNT=$(echo "$MISSING" | ${lib.getExe pkgs.jq} 'length')
            if [ "$COUNT" -gt 0 ]; then
              echo "$COUNT catalog entry/entries missing from root package.json:"
              echo "$MISSING" | ${lib.getExe pkgs.jq} -r '.[]' | while read -r pkg; do
                VER=$(echo "$MANIFEST_CATALOG" | ${lib.getExe pkgs.jq} -r --arg k "$pkg" '.[$k]')
                echo "  $pkg = $VER"
              done
              echo ""
              echo "Run: sp catalog sync"
              exit 1
            fi
          '';
        };
      };
    };
  };
}
