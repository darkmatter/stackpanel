#!/usr/bin/env bash
# Generate .proto files from Nix schemas and run buf generate.
#
# Entity schemas live in nix/stackpanel/db/schemas/*.proto.nix. Modules
# describe their settings at runtime; their SpFields are not buf inputs.
#
# Usage:
#   ./generate.sh           # Generate all protos and run buf
#   ./generate.sh proto     # Only generate .proto files from Nix
#   ./generate.sh buf       # Only run buf generate (assumes protos exist)
#   ./generate.sh clean     # Remove generated bindings, preserving proto inputs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKPANEL_DIR="$SCRIPT_DIR/../../nix/stackpanel"
NIX_SCHEMAS_DIR="$STACKPANEL_DIR/db/schemas"
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

	mkdir -p "$(dirname "$PROTO_OUT/$output_name")"
	nix eval --impure --raw --expr "
    let
      lib = (import <nixpkgs> {}).lib;
      proto = import $PROTO_LIB { inherit lib; };
      schema = import $schema_file { inherit lib; };
    in proto.renderProtoFile schema
  " >"$PROTO_OUT/${output_name}"

	echo "  ✓ ${output_name}"
}

# Only database entity schemas have a protobuf projection.
find_entity_schemas() {
	find "$NIX_SCHEMAS_DIR" -type f -name '*.proto.nix' ! -name '_*' -print0
}

# Generate all .proto files from Nix
cmd_proto() {
	echo "→ Generating .proto files from Nix..."
	mkdir -p "$PROTO_OUT"

	local count=0 schema_file
	while IFS= read -r -d '' schema_file; do
		generate_proto_file "$schema_file"
		count=$((count + 1))
	done < <(find_entity_schemas)

	if [[ $count -eq 0 ]]; then
		echo "  No schemas found"
		echo "  Entity schemas: $NIX_SCHEMAS_DIR/*.proto.nix"
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
		"$buf_bin" generate --template buf.gen.legacy.yaml
	else
		echo "  buf not found in PATH, using nix-shell..."
		nix-shell -p buf go --run "buf generate && buf generate --template buf.gen.legacy.yaml"
	fi

	echo "✓ Generated code to $GEN_OUT"
}

# Clean generated files
cmd_clean() {
	echo "→ Cleaning generated bindings (keeping .proto inputs)..."
	# gen/ also contains the handwritten TS barrel and Go module metadata.
	if [[ -d "$GEN_OUT" ]]; then
		find "$GEN_OUT" -type f \( -name '*.pb.go' -o -name '*.connect.go' -o \
			-name '*.json' -o -name '*.js' -o -name '*.ts' \) ! -name index.ts -delete
	fi
	rm -f "$SCRIPT_DIR/../../apps/stackpanel-go/internal/agent/server/connect_entities_gen.go"
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
	echo "  clean  - Remove generated bindings (keep proto inputs)"
	echo "  all    - Generate protos and run buf (default)"
	exit 1
	;;
esac
