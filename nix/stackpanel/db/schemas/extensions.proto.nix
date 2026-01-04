# ==============================================================================
# extensions.proto.nix
#
# Protobuf schema for extensions/plugins configuration.
# Defines extensions and plugins configuration for the project.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "extensions.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  enums = {
    SourceType = proto.mkEnum {
      name = "SourceType";
      description = "Source type for extensions";
      values = [
        "SOURCE_TYPE_UNSPECIFIED"
        "SOURCE_TYPE_GITHUB"
        "SOURCE_TYPE_NPM"
        "SOURCE_TYPE_LOCAL"
        "SOURCE_TYPE_URL"
      ];
    };
  };

  messages = {
    # Root extensions configuration
    Extensions = proto.mkMessage {
      name = "Extensions";
      description = "Extensions and plugins configuration";
      fields = {
        enabled = proto.bool 1 "Enable extensions system";
        auto_update = proto.bool 2 "Automatically check for extension updates";
        registry = proto.string 3 "Default extension registry URL";
        extensions = proto.map "string" "Extension" 4 "Installed extensions by key";
      };
    };

    # Extension configuration
    Extension = proto.mkMessage {
      name = "Extension";
      description = "Extension configuration";
      fields = {
        name = proto.string 1 "Display name of the extension";
        enabled = proto.bool 2 "Whether this extension is enabled";
        source = proto.message "Source" 3 "Extension source configuration";
        version = proto.optional (proto.string 4 "Version constraint (e.g., '^1.0.0', '~2.3', 'latest')");
        priority = proto.int32 5 "Load order priority (lower = earlier)";
        dependencies = proto.repeated (proto.string 6 "Other extensions this depends on");
        tags = proto.repeated (proto.string 7 "Tags for categorizing/filtering extensions");
      };
    };

    # Extension source configuration
    Source = proto.mkMessage {
      name = "Source";
      description = "Extension source configuration";
      fields = {
        type = proto.message "SourceType" 1 "Source type for the extension";
        repo = proto.optional (proto.string 2 "GitHub repository (owner/repo) for github source type");
        package = proto.optional (proto.string 3 "NPM package name for npm source type");
        path = proto.optional (proto.string 4 "Local path for local source type");
        url = proto.optional (proto.string 5 "URL for url source type");
        ref = proto.optional (proto.string 6 "Git ref (branch, tag, commit) for github source type");
      };
    };
  };
}
