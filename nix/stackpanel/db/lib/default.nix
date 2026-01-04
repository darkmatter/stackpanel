# ==============================================================================
# nix/stackpanel/db/lib/default.nix
#
# Database schema library exports.
#
# Exports:
#   - proto: Protobuf schema generation library (primary)
#   - types: Legacy JSON Schema types (kept for compatibility)
# ==============================================================================
{ lib }:
{
  # Primary: Protobuf-based schema generation
  proto = import ./proto.nix { inherit lib; };

  # Legacy: JSON Schema types (deprecated, kept for compatibility)
  types = import ./types.nix { inherit lib; };
}
