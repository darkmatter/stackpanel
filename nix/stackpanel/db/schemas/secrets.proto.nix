# ==============================================================================
# secrets.proto.nix
#
# Protobuf schema for secrets management configuration.
# Simplified to use master keys only - no per-user or per-environment keys.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "secrets.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # secrets.nix - Secrets management configuration
    # type: stackpanel.secrets
    # See: https://stackpanel.dev/docs/secrets
    {
      # enable = true;
      #
      # # Directory containing SOPS-encrypted secrets (legacy layout)
      # # Usually .stackpanel/secrets
      # input-directory = ".stackpanel/secrets";
      #
      # # Master keys for encrypting/decrypting secrets
      # # Each secret specifies which master keys can decrypt it
      # master-keys = {
      #   # Default local key - auto-generated, always works
      #   local = {
      #     age-pub = "age1...";  # computed from private key
      #     ref = "ref+file://.stackpanel/state/keys/local.txt";
      #   };
      #   
      #   # Team dev key - stored in AWS SSM
      #   dev = {
      #     age-pub = "age1...";
      #     ref = "ref+awsssm://stackpanel/keys/dev";
      #   };
      #   
      #   # Production key
      #   prod = {
      #     age-pub = "age1...";
      #     ref = "ref+awsssm://stackpanel/keys/prod";
      #   };
      # };
      #
      # # System-level AGE public keys (CI/deploy)
      # system-keys = [
      #   # "age1..."
      # ];
      #
      # # Code generation targets for type-safe env access
      # codegen = {
      #   typescript = {
      #     name = "env";
      #     directory = "packages/env/src/generated";
      #     language = "typescript";
      #   };
      # };
      #
      # # Environment-specific configs (SOPS sources + recipients)
      # environments = {
      #   dev = {
      #     name = "dev";
      #     sources = [ "shared" "dev" ];
      #     public-keys = [
      #       "age1..."
      #     ];
      #   };
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = { };

  messages = {
    CodegenTarget = proto.mkMessage {
      name = "CodegenTarget";
      description = "Code generation target for secrets/env access";
      fields = {
        name = proto.optional (
          proto.string 1 "Name of the generated package/module (defaults to the target key)"
        );
        directory = proto.optional (proto.string 2 "Output directory for generated code (repo-relative)");
        language = proto.optional (
          proto.string 3 ''
            Target language for generated code (e.g., "typescript", "go", "python").
            Informational only for now; codegen selection is based on the target key.
          ''
        );
      };
    };

    Environment = proto.mkMessage {
      name = "Environment";
      description = "Environment-specific secrets configuration";
      fields = {
        name = proto.optional (proto.string 1 "Name of the environment (e.g., dev, staging, production)");
        sources = proto.repeated (
          proto.string 2 ''
            List of SOPS-encrypted source files for this environment (without .yaml extension).
            These files are decrypted and merged to provide secrets for the environment.
          ''
        );
        public_keys = proto.repeated (
          proto.string 3 ''
            AGE public keys that can decrypt secrets for this environment.
            New secrets for this env are encrypted to these recipients.
          ''
        );
      };
    };

    # Secrets group — access control boundary for secrets
    SecretsGroup = proto.mkMessage {
      name = "SecretsGroup";
      description = ''
        A secrets group is an access control boundary.
        Each group has its own AGE keypair. The private key is stored externally
        (e.g., AWS SSM) so that IAM policies control who can decrypt that group's secrets.
        Variables specify which group(s) they belong to via the master-keys field.
      '';
      fields = {
        age_pub = proto.optional (
          proto.string 1 ''
            AGE public key for this group. Set after running `secrets:init-group <name>`.
            Format: age1... (bech32-encoded)
          ''
        );
        ssm_path = proto.optional (
          proto.string 2 ''
            SSM Parameter Store path where the AGE private key is stored.
            Defaults to /{chamber.service-prefix}/keys/{group-name}.
            Example: /my-org/my-repo/keys/dev
          ''
        );
        ref = proto.optional (
          proto.string 3 ''
            Vals reference that resolves to the AGE private key.
            Auto-computed from ssm-path as ref+awsssm://{ssm-path} when using chamber backend.
            Can be overridden for other backends (Vault, file, etc.).
          ''
        );
        key_cmd = proto.optional (
          proto.string 4 ''
            Shell command that outputs the AGE private key to stdout.
            Used by SOPS_AGE_KEY_CMD to lazily retrieve the group's private key.
            Defaults to: sops --decrypt .stackpanel/secrets/keys/<group>.enc.age
            Override for alternative key stores, e.g.:
              - chamber read keys/stackpanel/dev current -q
              - op read 'op://vault/stackpanel/dev-age-key'
              - aws ssm get-parameter --name /keys/dev --with-decryption --query Parameter.Value --output text
          ''
        );
      };
    };

    # Root secrets configuration
    Secrets = proto.mkMessage {
      name = "Secrets";
      description = "Secrets management configuration";
      fields = {
        enable = proto.bool 1 "Enable secrets management";
        master_keys = proto.map "string" "MasterKey" 2 ''
          Master keys for encrypting/decrypting secrets.
          Each secret specifies which master keys can decrypt it via the master-keys field.
          A default "local" key is auto-generated if no keys are configured.
        '';
        input_directory = proto.optional (
          proto.string 3 ''
            Directory containing SOPS-encrypted secrets (legacy SOPS layout).
            Used when decrypting/merging YAML sources defined under environments.
          ''
        );
        secrets_dir = proto.optional (
          proto.string 4 "Directory where secret .age files are stored (default: .stackpanel/secrets)"
        );
        system_keys = proto.repeated (
          proto.string 5 ''
            System-level AGE public keys (CI, deploy servers, etc.).
            These keys can decrypt all secrets regardless of environment restrictions.
          ''
        );
        environments = proto.map "string" "Environment" 6 ''
          Environment-specific secrets configuration (SOPS sources + recipients).
          Keyed by environment identifier (e.g., dev, staging, prod).
        '';
        codegen = proto.map "string" "CodegenTarget" 7 ''
          Code generation targets keyed by name (e.g., typescript, go, python).
          Used to drive language-specific env/secret helpers.
        '';
        groups = proto.map "string" "SecretsGroup" 8 ''
          Secrets groups for access control. Each group has an AGE keypair with
          the private key stored externally (e.g., SSM). Secrets are encrypted to
          group public keys, and IAM policies control who can retrieve the private key.
          Default groups: dev, prod.
        '';
      };
    };

    # Master key configuration
    MasterKey = proto.mkMessage {
      name = "MasterKey";
      description = "A master key for encrypting/decrypting secrets";
      fields = {
        age_pub = proto.string 1 ''
          AGE public key for encrypting secrets to this key.
          Format: age1... (bech32-encoded)
        '';
        ref = proto.string 2 ''
          Vals reference that resolves to the AGE private key.
          Examples:
            - ref+file://.stackpanel/state/keys/local.txt (local file)
            - ref+awsssm://stackpanel/keys/dev (AWS SSM Parameter Store)
            - ref+vault://secret/data/stackpanel/prod#key (HashiCorp Vault)
        '';
        resolve_cmd = proto.optional (
          proto.string 3 ''
            Custom command to resolve the private key (overrides ref).
            The command should output the AGE private key to stdout.
            Example: op read 'op://vault/stackpanel/age-key'
          ''
        );
      };
    };
  };
}
