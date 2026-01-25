# ==============================================================================
# variables.proto.nix
#
# Protobuf schema for workspace variables.
#
# Variables are simple key-value pairs where:
# - ID: Path-based identifier like /dev/DATABASE_URL or /computed/apps/web/port
# - Value: Either a literal string or a vals reference (ref+sops://, ref+awsssm://, etc.)
#
# The ID format determines the source:
# - /dev/*, /prod/*, /staging/* → SOPS-encrypted secrets in corresponding .yaml file
# - /computed/* → Computed values from Nix modules (read-only)
# - /literal/* → User-defined literal values (optional organization)
#
# Secrets are stored in SOPS-encrypted YAML files:
# - .stackpanel/secrets/dev.yaml → All /dev/* variables
# - .stackpanel/secrets/prod.yaml → All /prod/* variables
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "variables.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = { };

  messages = {
    # A single variable entry
    Variable = proto.mkMessage {
      name = "Variable";
      description = "A workspace variable (secret, literal, or vals reference)";
      fields = {
        id = proto.optional (proto.string 1 ''
          Path-based identifier. Format: /<keygroup>/<VARNAME>
          
          Examples:
            /dev/DATABASE_URL      → Secret in dev.yaml
            /prod/API_KEY          → Secret in prod.yaml
            /computed/apps/web/port → Computed by Nix module
        '');
        value = proto.string 2 ''
          The value - either a literal string or a vals reference.
          
          Literals:
            "postgresql://localhost:5432/dev"
            "3000"
          
          Vals references:
            "ref+sops://.stackpanel/secrets/dev.yaml#/DATABASE_URL"
            "ref+awsssm://prod/api-key"
            "ref+exec://echo $RANDOM"
        '';
      };
    };

    # Collection of variables
    Variables = proto.mkMessage {
      name = "Variables";
      description = "Map of variable ID to Variable";
      fields = {
        variables = proto.map "string" "Variable" 1 ''
          Map of variable ID to Variable object.
          Each Variable contains at minimum a value field.
        '';
      };
    };
  };
}
