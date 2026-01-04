# ==============================================================================
# _template.proto.nix
#
# Reference template for creating protobuf schemas in Nix.
# Copy this file and modify for your entity.
#
# Usage:
#   1. Copy: cp _template.proto.nix myentity.proto.nix
#   2. Update package, messages, enums as needed
#   3. Generate: ./generate-proto.sh myentity
#   4. Use buf: buf generate
#
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  # Output filename (should match this file's name)
  name = "template.proto";

  # Protobuf package name
  package = "stackpanel.db";

  # Language-specific options
  options = {
    go_package = "github.com/darkmatter/stackpanel/gen/db";
    # java_package = "com.example.stackpanel.db";
    # csharp_namespace = "Stackpanel.Db";
  };

  # Import other proto files if needed
  # imports = [
  #   "google/protobuf/timestamp.proto"
  #   "google/protobuf/wrappers.proto"
  # ];

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enums = {
    # Enum values should be UPPER_SNAKE_CASE with a prefix
    # First value should be UNSPECIFIED = 0 (proto3 convention)
    Status = proto.mkEnum {
      name = "Status";
      description = "Status of the entity";
      values = [
        "STATUS_UNSPECIFIED"
        "STATUS_ACTIVE"
        "STATUS_INACTIVE"
        "STATUS_PENDING"
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------
  messages = {
    # Main entity message
    Template = proto.mkMessage {
      name = "Template";
      description = "Example entity demonstrating all field types";
      fields = {
        # =====================================================================
        # IMPORTANT: Field numbers are REQUIRED and must be explicit!
        #
        # Format: proto.<type> <number> "description"
        #
        # Rules:
        #   - Numbers must be unique within a message
        #   - Numbers 1-15 use 1 byte (use for frequently-used fields)
        #   - Numbers 16-2047 use 2 bytes
        #   - Never reuse a number after deleting a field
        #   - Reserved: 19000-19999 (protobuf internal)
        # =====================================================================

        # -----------------------------------------------------------------------
        # Scalar types
        # -----------------------------------------------------------------------

        # Required string field
        name = proto.string 1 "Display name (required)";

        # Optional string field
        description = proto.optional (proto.string 2 "Optional description");

        # Integer types
        count = proto.int32 3 "32-bit integer";
        big_count = proto.int64 4 "64-bit integer";
        positive_count = proto.uint32 5 "Unsigned 32-bit integer";

        # Boolean
        enabled = proto.bool 6 "Whether this is enabled";

        # Floating point
        score = proto.double 7 "64-bit floating point";
        rating = proto.float 8 "32-bit floating point";

        # Binary data
        data = proto.bytes 9 "Raw binary data";

        # -----------------------------------------------------------------------
        # Compound types
        # -----------------------------------------------------------------------

        # Repeated (array/list)
        tags = proto.repeated (proto.string 10 "List of tags");

        # Map (key-value): proto.map <keyType> <valueType> <number> "description"
        metadata = proto.map "string" "string" 11 "Key-value metadata";

        # Reference to another message: proto.message <typeName> <number> "description"
        status = proto.message "Status" 12 "Current status";

        # Repeated message reference
        # items = proto.repeated (proto.message "Item" 13 "List of items");

        # -----------------------------------------------------------------------
        # Multiline descriptions
        # -----------------------------------------------------------------------
        config = proto.string 14 ''
          Configuration JSON string.

          This field accepts a JSON-encoded configuration object.
          See documentation for the expected schema.'';
      };
    };

    # Wrapper message for map-based collections (common pattern)
    Templates = proto.mkMessage {
      name = "Templates";
      description = "Collection of templates keyed by ID";
      fields = {
        templates = proto.map "string" "Template" 1 "Map of template ID to template";
      };
    };

    # Nested message example - define separately and reference by name
    # Item = proto.mkMessage {
    #   name = "Item";
    #   description = "A nested item";
    #   fields = {
    #     id = proto.string 1 "Item ID";
    #     value = proto.int32 2 "Item value";
    #   };
    # };
  };

  # ---------------------------------------------------------------------------
  # Services (for gRPC/Connect/tRPC)
  # ---------------------------------------------------------------------------
  # services = {
  #   TemplateService = proto.mkService {
  #     name = "TemplateService";
  #     description = "Service for managing templates";
  #     methods = {
  #       GetTemplate = proto.mkMethod {
  #         input = "GetTemplateRequest";
  #         output = "Template";
  #         description = "Get a template by ID";
  #       };
  #       ListTemplates = proto.mkMethod {
  #         input = "ListTemplatesRequest";
  #         output = "Templates";
  #         description = "List all templates";
  #       };
  #       # Streaming example
  #       WatchTemplates = proto.mkMethod {
  #         input = "WatchTemplatesRequest";
  #         output = "Template";
  #         streaming = "server";  # "client" | "server" | "bidirectional"
  #         description = "Watch for template changes";
  #       };
  #     };
  #   };
  # };
}

# ==============================================================================
# Quick Reference
# ==============================================================================
#
# Field constructors (all require explicit field number):
#   proto.string <num> "desc"     → string
#   proto.int32 <num> "desc"      → int32
#   proto.int64 <num> "desc"      → int64
#   proto.uint32 <num> "desc"     → uint32
#   proto.uint64 <num> "desc"     → uint64
#   proto.bool <num> "desc"       → bool
#   proto.double <num> "desc"     → double
#   proto.float <num> "desc"      → float
#   proto.bytes <num> "desc"      → bytes
#
# Field modifiers:
#   proto.optional field              → optional T
#   proto.repeated field              → repeated T
#   proto.map "K" "V" <num> "desc"    → map<K, V>
#   proto.message "T" <num> "desc"    → T (reference to message)
#
# Type constructors:
#   proto.mkEnum { name, values, description? }
#   proto.mkMessage { name, fields, description?, nested? }
#   proto.mkService { name, methods, description? }
#   proto.mkMethod { input, output, description?, streaming? }
#   proto.mkProtoFile { name, package, messages?, enums?, services?, options?, imports? }
#
# ==============================================================================
