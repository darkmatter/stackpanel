# ==============================================================================
# nix/stackpanel/db/lib/default.nix
#
# Database schema library exports.
#
# Exports:
#   - proto: Protobuf schema generation library (primary)
#   - options: Proto → Nix option conversion utilities
#   - mkOpt: Helper for defining options that extend proto schemas
#   - types: Legacy JSON Schema types (kept for compatibility)
#   - dataLoader: Load .nix and .json data files
# ==============================================================================
{ lib }:
{
  # Primary: Protobuf-based schema generation
  proto = import ./proto.nix { inherit lib; };

  # Proto → Nix options: Convert proto messages to Nix module options
  options = import ./options.nix { inherit lib; };

  # mkOpt: Helper for extending proto-derived options
  # Enforces deliberate option definition and prevents field duplication
  mkOptLib = import ./mkOpt.nix { inherit lib; };

  # Legacy: JSON Schema types (deprecated, kept for compatibility)
  types = import ./types.nix { inherit lib; };

  # Data loader: Load .nix and .json files from data directories
  dataLoader = import ./data-loader.nix { inherit lib; };
}
