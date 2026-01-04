#!/usr/bin/env bash
# Generate .proto files from Nix schemas and run buf generate.
#
# Usage:
#   ./generate.sh           # Generate all protos and run buf
#   ./generate.sh proto     # Only generate .proto files from Nix
#   ./generate.sh buf       # Only run buf generate (assumes protos exist)
#   ./generate.sh clean     # Remove generated files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_SCHEMAS_DIR="$SCRIPT_DIR/../../nix/stackpanel/db/schemas"
PROTO_OUT="$SCRIPT_DIR/proto"
GEN_OUT="$SCRIPT_DIR/gen"

# Generate .proto from a single Nix schema
# $1 = relative path without extension (e.g., "users" or "external/github-collaborators")
generate_proto() {
  local relpath="$1"
  local schema_file="$NIX_SCHEMAS_DIR/${relpath}.proto.nix"

  if [[ ! -f "$schema_file" ]]; then
    echo "  ⚠ Schema not found: $schema_file" >&2
    return 1
  fi

  # Get the output filename from the schema's name attribute
  local output_name
  output_name=$(nix eval --impure --raw --expr "
    let
      lib = (import <nixpkgs> {}).lib;
      schema = import $schema_file { inherit lib; };
    in schema.name
  ")

  nix eval --impure --raw --expr "
    let
      lib = (import <nixpkgs> {}).lib;
      proto = import $NIX_SCHEMAS_DIR/../lib/proto.nix { inherit lib; };
      schema = import $schema_file { inherit lib; };
    in proto.renderProtoFile schema
  " > "$PROTO_OUT/${output_name}"

  echo "  ✓ ${output_name}"
}

# Find all .proto.nix schemas (excluding _template), returns relative paths without extension
find_schemas() {
  find "$NIX_SCHEMAS_DIR" -name "*.proto.nix" | while read -r file; do
    # Get path relative to schemas dir, remove .proto.nix extension
    relpath="${file#$NIX_SCHEMAS_DIR/}"
    relpath="${relpath%.proto.nix}"
    # Skip templates
    basename="${relpath##*/}"
    if [[ "$basename" != _* ]]; then
      echo "$relpath"
    fi
  done
}

# Generate all .proto files from Nix
cmd_proto() {
  echo "→ Generating .proto files from Nix..."
  mkdir -p "$PROTO_OUT"

  local count=0
  for schema in $(find_schemas); do
    if generate_proto "$schema"; then
      ((count++)) || true
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo "  No schemas found in $NIX_SCHEMAS_DIR"
    echo "  Create schemas with: cp _template.proto.nix myschema.proto.nix"
    return 1
  fi

  echo "✓ Generated $count proto file(s) to $PROTO_OUT"
}

# Find buf binary
find_buf() {
  if command -v buf &>/dev/null; then
    echo "buf"
  elif [[ -x "/nix/var/nix/profiles/default/bin/buf" ]]; then
    echo "/nix/var/nix/profiles/default/bin/buf"
  else
    echo ""
  fi
}

# Run buf generate
cmd_buf() {
  echo "→ Running buf generate..."
  cd "$SCRIPT_DIR"

  if [[ ! -d "$PROTO_OUT" ]] || [[ -z "$(ls -A "$PROTO_OUT" 2>/dev/null)" ]]; then
    echo "  ⚠ No proto files found. Run: $0 proto" >&2
    return 1
  fi

  local buf_bin
  buf_bin=$(find_buf)

  if [[ -n "$buf_bin" ]]; then
    "$buf_bin" generate
  else
    echo "  buf not found in PATH, using nix-shell..."
    nix-shell -p buf --run "buf generate"
  fi

  echo "✓ Generated code to $GEN_OUT"
}

# Clean generated files
cmd_clean() {
  echo "→ Cleaning generated files..."
  rm -rf "$PROTO_OUT" "$GEN_OUT"
  echo "✓ Cleaned"
}

# Main
case "${1:-all}" in
  proto)
    cmd_proto
    ;;
  buf)
    cmd_buf
    ;;
  clean)
    cmd_clean
    ;;
  all)
    cmd_proto
    echo
    cmd_buf
    ;;
  *)
    echo "Usage: $0 [proto|buf|clean|all]"
    echo
    echo "Commands:"
    echo "  proto  - Generate .proto files from Nix schemas"
    echo "  buf    - Run buf generate on .proto files"
    echo "  clean  - Remove generated files"
    echo "  all    - Generate protos and run buf (default)"
    exit 1
    ;;
esac
