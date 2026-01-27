#!/usr/bin/env bash
# Generate .proto files from Nix schemas and run buf generate.
#
# Schema discovery:
#   1. Entity schemas:  nix/stackpanel/db/schemas/*.proto.nix
#   2. Module schemas:  nix/stackpanel/modules/*/schema.nix (convention)
#
# Remote modules can register schemas via stackpanel.protoSchemas (future).
#
# Usage:
#   ./generate.sh           # Generate all protos and run buf
#   ./generate.sh proto     # Only generate .proto files from Nix
#   ./generate.sh buf       # Only run buf generate (assumes protos exist)
#   ./generate.sh clean     # Remove generated files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKPANEL_DIR="$SCRIPT_DIR/../../nix/stackpanel"
NIX_SCHEMAS_DIR="$STACKPANEL_DIR/db/schemas"
NIX_MODULES_DIR="$STACKPANEL_DIR/modules"
PROTO_LIB="$STACKPANEL_DIR/db/lib/proto.nix"
PROTO_OUT="$SCRIPT_DIR/proto"
GEN_OUT="$SCRIPT_DIR/gen"

# Generate .proto from a single Nix schema file (absolute path)
generate_proto_file() {
	local schema_file="$1"

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
  " 2>/dev/null) || {
		echo "  ⚠ Failed to evaluate schema name: $schema_file" >&2
		return 1
	}

	if [[ -z "$output_name" ]]; then
		echo "  ⚠ Schema has no name: $schema_file" >&2
		return 1
	fi

	nix eval --impure --raw --expr "
    let
      lib = (import <nixpkgs> {}).lib;
      proto = import $PROTO_LIB { inherit lib; };
      schema = import $schema_file { inherit lib; };
    in proto.renderProtoFile schema
  " >"$PROTO_OUT/${output_name}"

	echo "  ✓ ${output_name}"
}

# Find all schema files from both entity schemas and module schemas
find_all_schemas() {
	# 1. Entity schemas: db/schemas/*.proto.nix (excluding _template)
	if [[ -d "$NIX_SCHEMAS_DIR" ]]; then
		find "$NIX_SCHEMAS_DIR" -name "*.proto.nix" | while read -r file; do
			basename="${file##*/}"
			if [[ "$basename" != _* ]]; then
				echo "$file"
			fi
		done
	fi

	# 2. Module schemas: modules/*/schema.nix (convention-based)
	if [[ -d "$NIX_MODULES_DIR" ]]; then
		find "$NIX_MODULES_DIR" -maxdepth 2 -name "schema.nix" -type f | while read -r file; do
			echo "$file"
		done
	fi
}

# Generate all .proto files from Nix
cmd_proto() {
	echo "→ Generating .proto files from Nix..."
	mkdir -p "$PROTO_OUT"

	local count=0
	for schema_file in $(find_all_schemas); do
		if generate_proto_file "$schema_file"; then
			((count++)) || true
		fi
	done

	if [[ $count -eq 0 ]]; then
		echo "  No schemas found"
		echo "  Entity schemas: $NIX_SCHEMAS_DIR/*.proto.nix"
		echo "  Module schemas: $NIX_MODULES_DIR/*/schema.nix"
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
