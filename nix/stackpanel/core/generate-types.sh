#!/usr/bin/env bash
# ==============================================================================
# generate-types.sh
#
# Generate TypeScript and Go types from Nix protobuf schemas.
#
# This script wraps the proto generation pipeline:
#   1. Generates .proto files from nix/stackpanel/db/schemas/*.proto.nix
#   2. Runs buf generate to create Go and TypeScript types
#
# Usage:
#   ./generate-types.sh           # Generate protos and run buf (full pipeline)
#   ./generate-types.sh proto     # Only generate .proto files from Nix
#   ./generate-types.sh buf       # Only run buf generate (assumes protos exist)
#   ./generate-types.sh clean     # Remove generated files
#
# Output locations:
#   - Proto files:      packages/proto/proto/*.proto
#   - Go types:         packages/proto/gen/go/*.pb.go
#   - TypeScript types: packages/proto/gen/ts/*.ts
#
# The .proto.nix files are the SOURCE OF TRUTH. This ensures:
#   - Types are always in sync with the Nix configuration
#   - No divergence between TypeScript and Go types
#   - Single point of maintenance
#
# Migration Note:
#   This script replaces the old JSON Schema + quicktype approach.
#   The new protobuf-based pipeline provides better tooling, cross-language
#   compatibility, and support for gRPC/Connect services.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Proto package location
PROTO_PACKAGE="$REPO_ROOT/packages/proto"
PROTO_GENERATE_SCRIPT="$PROTO_PACKAGE/generate.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}→${NC} $1"
}

success() {
  echo -e "${GREEN}✓${NC} $1"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

error() {
  echo -e "${RED}✗${NC} $1" >&2
  exit 1
}

# Validate proto package exists
if [[ ! -d "$PROTO_PACKAGE" ]]; then
  error "Proto package not found: $PROTO_PACKAGE"
fi

if [[ ! -f "$PROTO_GENERATE_SCRIPT" ]]; then
  error "Proto generate script not found: $PROTO_GENERATE_SCRIPT"
fi

# Determine mode
MODE="${1:-all}"

case "$MODE" in
  proto)
    log "Generating .proto files from Nix schemas..."
    "$PROTO_GENERATE_SCRIPT" proto
    success "Proto files generated!"
    ;;
  buf)
    log "Running buf generate..."
    "$PROTO_GENERATE_SCRIPT" buf
    success "Go and TypeScript types generated!"
    ;;
  clean)
    log "Cleaning generated files..."
    "$PROTO_GENERATE_SCRIPT" clean
    success "Cleaned!"
    ;;
  all)
    log "Running full proto generation pipeline..."
    echo
    "$PROTO_GENERATE_SCRIPT" all
    echo
    success "All types generated from Nix proto schemas!"
    echo
    echo "Generated files:"
    echo "  Proto:      $PROTO_PACKAGE/proto/*.proto"
    echo "  Go:         $PROTO_PACKAGE/gen/go/*.pb.go"
    echo "  TypeScript: $PROTO_PACKAGE/gen/ts/*.ts"
    ;;
  help|--help|-h)
    cat << EOF
Usage: $0 [proto|buf|clean|all|help]

Commands:
  proto  - Generate .proto files from Nix schemas (nix/stackpanel/db/schemas/*.proto.nix)
  buf    - Run buf generate on .proto files (creates Go and TypeScript)
  clean  - Remove all generated files
  all    - Run full pipeline: proto + buf (default)
  help   - Show this help message

Output locations:
  Proto files:      packages/proto/proto/*.proto
  Go types:         packages/proto/gen/go/*.pb.go
  TypeScript types: packages/proto/gen/ts/*.ts

The .proto.nix files in nix/stackpanel/db/schemas/ are the SOURCE OF TRUTH.

Example workflow:
  1. Edit a schema:     vim nix/stackpanel/db/schemas/users.proto.nix
  2. Regenerate types:  $0
  3. Use in Go:         import "github.com/darkmatter/stackpanel/packages/proto/gen/go"
  4. Use in TypeScript: import { User } from '@stackpanel/proto/gen/ts/users'
EOF
    ;;
  *)
    error "Unknown mode: $MODE. Use 'proto', 'buf', 'clean', 'all', or 'help'"
    ;;
esac
