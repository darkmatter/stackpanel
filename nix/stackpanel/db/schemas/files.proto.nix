# ==============================================================================
# files.proto.nix
#
# Protobuf schema for generated files configuration.
# Defines file entries that stackpanel generates into the project workspace.
#
# Files are declared via stackpanel.files.entries in Nix modules and
# materialized by the write-files command on shell entry.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "files.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = {
    FileType = proto.mkEnum {
      name = "FileType";
      description = "Type of file content source";
      values = [
        "FILE_TYPE_UNSPECIFIED"
        "FILE_TYPE_TEXT"
        "FILE_TYPE_DERIVATION"
        "FILE_TYPE_JSON"
      ];
    };
  };

  messages = {
    # Individual generated file entry
    GeneratedFile = proto.mkMessage {
      name = "GeneratedFile";
      description = "A file to be generated into the project workspace";
      fields = {
        path = proto.string 1 "Relative path from project root where file will be written";
        type = proto.message "FileType" 2 "Type of content source (text or derivation)";
        enable = proto.bool 3 "Whether this file should be generated";
        mode = proto.optional (proto.string 4 "File permissions (e.g., '0755')");
        source = proto.optional (proto.string 5 "Module or component that generated this file");
        description = proto.optional (proto.string 6 "Human-readable description of the file's purpose");
        store_path = proto.optional (
          proto.string 7 "Nix store path containing the file content (for derivation type)"
        );
        text = proto.optional (
          proto.string 8 "Inline text content (for text type, may be truncated for large files)"
        );
      };
    };

    # Collection of generated files
    GeneratedFiles = proto.mkMessage {
      name = "GeneratedFiles";
      description = "Collection of all generated file entries";
      fields = {
        enable = proto.bool 1 "Whether file generation is enabled globally";
        entries = proto.map "string" "GeneratedFile" 2 "Map of file path to file configuration";
      };
    };
  };
}
