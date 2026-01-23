# ==============================================================================
# nix/stackpanel/db/lib/mkOpt.nix
#
# Helper for defining Nix options that extend proto-derived schemas.
#
# This module enforces deliberate option definition by requiring all option
# definitions to explicitly choose either:
#   - db.extend.<schemaName> - extend a proto schema
#   - db.extend.none         - pure Nix options (no proto schema)
#
# The mkOpt function validates that:
#   1. The base attrset comes from db.extend.* (has the marker)
#   2. Extensions don't duplicate proto-defined fields
#
# Usage:
#   options.stackpanel.theme = db.mkOpt db.extend.theme {
#     # Nix-specific extensions only
#     config-file = lib.mkOption { ... };
#   };
#
#   options.stackpanel.devshell = db.mkOpt db.extend.none {
#     # Pure Nix options - no proto schema
#     packages = lib.mkOption { ... };
#   };
#
#   # For direct submodule use (strips marker):
#   { options = db.asOptions db.extend.app; }
#
#   # Convenience for submodule with extensions:
#   db.mkSubmodule db.extend.app { extra = lib.mkOption { ... }; }
#
# ==============================================================================
{ lib }:
let
  # The marker attribute name - used to validate that base comes from db.extend.*
  marker = "__db_extend_marker__";

  # Add marker to an options attrset
  # Called internally when building db.extend.* outputs
  withMarker = opts: opts // { ${marker} = true; };

  # The "none" base - for pure Nix options with no proto schema
  # Use this when the option has no corresponding proto definition
  none = { ${marker} = true; };

  # mkOpt: Merge proto-derived options with Nix-specific extensions
  #
  # Arguments:
  #   base       - Options from db.extend.* (or db.extend.none)
  #   extensions - Additional Nix-specific options to add
  #
  # Returns:
  #   Merged options attrset (marker removed)
  #
  # Throws:
  #   - If base doesn't have the marker (not from db.extend.*)
  #   - If extensions duplicate any proto-defined fields
  #
  mkOpt =
    base: extensions:
    if !(base ? ${marker}) then
      throw ''
        mkOpt requires a db.extend.* as first argument.

        Use one of:
          db.mkOpt db.extend.theme { ... }   -- extend proto schema
          db.mkOpt db.extend.none { ... }    -- pure Nix options

        Available proto schemas can be found in: nix/stackpanel/db/schemas/
      ''
    else
      let
        # Get keys from base (excluding marker)
        baseKeys = lib.filter (k: k != marker) (builtins.attrNames base);

        # Get keys from extensions
        extKeys = builtins.attrNames extensions;

        # Find duplicates
        duplicates = lib.filter (k: builtins.elem k baseKeys) extKeys;

        # Force the duplicate check by including it in the result
        # If duplicates exist, this throws; otherwise returns the merged set
        checkedResult =
          if duplicates != [ ] then
            throw ''
              mkOpt: extensions duplicate proto-defined fields: ${lib.concatStringsSep ", " duplicates}

              These fields are already defined in the proto schema.
              Either:
                1. Remove them from extensions (use proto defaults)
                2. Update the proto schema in db/schemas/*.proto.nix
            ''
          else
            # Remove marker, merge base + extensions
            (removeAttrs base [ marker ]) // extensions;
      in
      checkedResult;

  # asOptions: Strip the marker from db.extend.* for direct use in submodules
  #
  # Use this when you need to use proto-derived options directly as a submodule's
  # options, without going through mkOpt (e.g., when combining with other modules).
  #
  # Example:
  #   { options = db.asOptions db.extend.app; }
  #   # Instead of: { options = removeAttrs db.extend.app [ "__db_extend_marker__" ]; }
  #
  asOptions =
    opts:
    if !(opts ? ${marker}) then
      throw ''
        asOptions requires a db.extend.* as argument.

        Use one of:
          db.asOptions db.extend.app
          db.asOptions db.extend.user
      ''
    else
      removeAttrs opts [ marker ];

  # mkSubmodule: Convenience for creating a submodule with proto options + extensions
  #
  # Returns { options = ...; } suitable for use in lib.types.submodule.
  #
  # Example:
  #   lib.types.submodule (db.mkSubmodule db.extend.app { extra = lib.mkOption { ... }; })
  #
  mkSubmodule = base: extensions: { options = mkOpt base extensions; };
in
{
  inherit mkOpt none withMarker marker asOptions mkSubmodule;
}
