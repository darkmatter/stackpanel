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
# - /dev/*, /prod/*, /staging/*, /shared/* → SOPS-encrypted secrets
# - /computed/* → Computed values from Nix modules (read-only)
# - /var/* → User-defined plaintext config (URLs, feature flags, log level)
#
# Secrets are stored in SOPS-encrypted YAML files:
# - .stack/secrets/dev.yaml → All /dev/* variables
# - .stack/secrets/prod.yaml → All /prod/* variables
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
        id = proto.optional (
          proto.withExample "/dev/DATABASE_URL" (
            proto.string 1 ''
              Path-based identifier. Format: /<keygroup>/<VARNAME>

              Examples:
                /dev/DATABASE_URL             → Secret in vars/dev.sops.yaml
                /var/API_BASE_URL             → Plaintext config
                /computed/apps/web/port       → Computed by Nix
                /computed/services/postgres/port → Service port
            ''
          )
        );
        value = proto.withExample "ref+sops://.stack/secrets/dev.yaml#/DATABASE_URL" (
          proto.string 2 ''
            The value - either a literal string or a vals reference.

            Literals:
              "postgresql://localhost:5432/dev"
              "3000"

            Vals references:
              "ref+sops://.stack/secrets/dev.yaml#/DATABASE_URL"
              "ref+awsssm://prod/api-key"
              "ref+exec://echo $RANDOM"
          ''
        );
      };
    };

    # Collection of variables
    Variables = proto.mkMessage {
      name = "Variables";
      description = "Map of variable ID to Variable";
      fields = {
        variables = proto.withExample {
          "/dev/DATABASE_URL" = {
            value = "ref+sops://.stack/secrets/vars/dev.sops.yaml#/DATABASE_URL";
          };
          "/dev/REDIS_URL" = {
            value = "ref+sops://.stack/secrets/vars/dev.sops.yaml#/REDIS_URL";
          };
          "/var/API_BASE_URL" = {
            value = "https://api.stackpanel-demo.localhost";
          };
          "/var/LOG_LEVEL" = {
            value = "info";
          };
          "/var/NODE_ENV" = {
            value = "development";
          };
          "/computed/apps/web/port" = {
            value = "6402";
          };
          "/computed/services/postgres/port" = {
            value = "6410";
          };
        } (proto.map "string" "Variable" 1 ''
          Map of variable ID to Variable object.
          Each Variable contains at minimum a value field.
        '');
      };
    };
  };
}
