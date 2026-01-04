# ==============================================================================
# secrets.proto.nix
#
# Protobuf schema for secrets management configuration.
# Defines the structure for secrets management and code generation.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "secrets.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  enums = {
    CodegenLanguage = proto.mkEnum {
      name = "CodegenLanguage";
      description = "Programming language for generated code";
      values = [
        "CODEGEN_LANGUAGE_UNSPECIFIED"
        "CODEGEN_LANGUAGE_TYPESCRIPT"
        "CODEGEN_LANGUAGE_GO"
      ];
    };
  };

  messages = {
    # Root secrets configuration
    Secrets = proto.mkMessage {
      name = "Secrets";
      description = "Secrets management configuration";
      fields = {
        enable = proto.bool 1 "Enable secrets management";
        input_directory = proto.string 2 "Directory where SOPS-encrypted secrets are stored";
        environments =
          proto.map "string" "SecretsEnvironment" 3
            "Environment-specific secrets configurations";
        codegen = proto.map "string" "Codegen" 4 "Code generation settings per target";
      };
    };

    # Environment-specific secrets configuration
    SecretsEnvironment = proto.mkMessage {
      name = "SecretsEnvironment";
      description = "Environment-specific secrets configuration";
      fields = {
        name = proto.string 1 "Name of the environment (e.g., 'production', 'staging')";
        public_keys = proto.repeated (
          proto.string 2 "AGE public keys that can decrypt secrets for this environment"
        );
        sources = proto.repeated (
          proto.string 3 "List of SOPS-encrypted source files for this environment (without .yaml extension)"
        );
      };
    };

    # Code generation settings
    Codegen = proto.mkMessage {
      name = "Codegen";
      description = "Code generation settings for a target language";
      fields = {
        name = proto.string 1 "Name of the generated code package";
        directory = proto.string 2 "Output directory for generated code (relative to project root)";
        language = proto.message "CodegenLanguage" 3 "Programming language for generated code";
      };
    };
  };
}
