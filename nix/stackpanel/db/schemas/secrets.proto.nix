# ==============================================================================
# secrets.proto.nix
#
# Protobuf schema for secrets management configuration.
# Current model: SOPS recipients and creation rules for grouped variables, with
# legacy master keys retained for older `.age` consumers.
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
     enable = true;

     # Directory containing SOPS-encrypted grouped variables
     # Usually .stack/secrets
     input-directory = ".stack/secrets";

     # Legacy master keys for .age/vals consumers, separate from SOPS recipients
     master-keys = {
       # Default local key - auto-generated, always works
       local = {
         age-pub = "age1...";  # computed from private key
         ref = "ref+file://.stack/keys/local.txt";
       };

       # Team dev key - stored in AWS SSM
       dev = {
         age-pub = "age1...";
         ref = "ref+awsssm://stackpanel/keys/dev";
       };

       # Production key
       prod = {
         age-pub = "age1...";
         ref = "ref+awsssm://stackpanel/keys/prod";
       };
     };

     # System-level AGE public keys (CI/deploy)
     system-keys = [
       # "age1..."
     ];

     # Code generation targets for type-safe env access
     codegen = {
       typescript = {
         name = "env";
         directory = "packages/gen/env/src";
         language = "typescript";
       };
     };

     # Legacy environment-specific configs (SOPS sources + recipients)
     environments = {
       dev = {
         name = "dev";
         sources = [ "shared" "dev" ];
         public-keys = [
           "age1..."
         ];
       };
     };
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
          proto.withExample "env" (
            proto.string 1 "Name of the generated package/module (defaults to the target key)"
          )
        );
        directory = proto.optional (
          proto.withExample "packages/gen/env/src" (
            proto.string 2 "Output directory for generated code (repo-relative)"
          )
        );
        language = proto.optional (
          proto.withExample "typescript" (
            proto.string 3 ''
              Target language for generated code (e.g., "typescript", "go", "python").
              Informational only for now; codegen selection is based on the target key.
            ''
          )
        );
      };
    };

    Environment = proto.mkMessage {
      name = "Environment";
      description = "Environment-specific secrets configuration";
      fields = {
        name = proto.optional (
          proto.withExample "dev" (proto.string 1 "Name of the environment (e.g., dev, staging, production)")
        );
        sources = proto.repeated (
          proto.withExample "shared" (
            proto.string 2 ''
              List of SOPS-encrypted source files for this environment (without .yaml extension).
              These files are decrypted and merged to provide secrets for the environment.
            ''
          )
        );
        public_keys = proto.repeated (
          proto.withExample "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1" (
            proto.string 3 ''
              AGE public keys that can decrypt secrets for this environment.
              New secrets for this env are encrypted to these recipients.
            ''
          )
        );
      };
    };

    # Secrets group — logical bucket for SOPS files
    SecretsGroup = proto.mkMessage {
      name = "SecretsGroup";
      description = ''
        Deprecated legacy secrets group metadata.
      '';
      fields = {
        age_pub = proto.optional (
          proto.withExample "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1" (
            proto.string 1 ''
              Deprecated. Group-level public keys are no longer used.
            ''
          )
        );
        ssm_path = proto.optional (
          proto.withExample "/stackpanel/keys/dev" (
            proto.string 2 ''
              Deprecated. Group-level private keys are no longer used.
            ''
          )
        );
        ref = proto.optional (
          proto.withExample "ref+awsssm:///stackpanel/keys/dev" (
            proto.string 3 ''
              Deprecated. Group-level private keys are no longer used.
            ''
          )
        );
        key_cmd = proto.optional (
          proto.withExample "op read 'op://vault/stackpanel/age-key'" (
            proto.string 4 ''
              Deprecated. Group-level private keys are no longer used.
            ''
          )
        );
      };
    };

    # Root secrets configuration
    Secrets = proto.mkMessage {
      name = "Secrets";
      description = "Secrets management configuration";
      fields = {
        enable = proto.withExample true (
          proto.bool 1 "Enable Stackpanel secret file management, recipient generation, and env codegen"
        );
        master_keys = proto.withExample {
          local = {
            "age-pub" = "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1";
            ref = "ref+file://.stack/keys/local.txt";
          };
        } (proto.map "string" "MasterKey" 2 ''
          Legacy master keys for `.age`/vals consumers.

          These keys are not SOPS recipients and do not control access to grouped
          variable files under `.stack/secrets/vars/`. Use
          `stackpanel.secrets.recipients`, `recipient-groups`, and `creation-rules`
          for the current SOPS flow.

          A default `local` key is configured for local bootstrap.
        '');
        input_directory = proto.optional (
          proto.withExample ".stack/secrets" (
            proto.string 3 ''
              Legacy directory containing SOPS-encrypted source files used by
              `environments.*.sources`.
            ''
          )
        );
        secrets_dir = proto.optional (
          proto.withExample ".stack/secrets" (
            proto.string 4 ''
              Secrets workspace directory (default: `.stack/secrets`).

              Grouped variables are stored under `vars/<group>.sops.yaml` inside
              this directory. Legacy `.age` files may also live here for older
              master-key based consumers.
            ''
          )
        );
        system_keys = proto.repeated (
          proto.withExample "age1ci1234ci1234ci1234ci1234ci1234ci1234ci1234ci1234ci1" (
            proto.string 5 ''
              Legacy system-level AGE public keys for older `.age` flows.

              For current grouped SOPS files, model CI/deploy access as explicit
              recipients and include them in the relevant creation rules.
            ''
          )
        );
        environments = proto.withExample {
          dev = {
            sources = [ "shared" "dev" ];
            "public-keys" = [ "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1" ];
          };
        } (proto.map "string" "Environment" 6 ''
          Legacy environment-specific secrets configuration for source merging.

          New variable definitions should use `stackpanel.variables` plus SOPS
          creation rules instead.
        '');
        codegen = proto.withExample {
          typescript = {
            name = "env";
            directory = "packages/gen/env/src";
            language = "typescript";
          };
        } (proto.map "string" "CodegenTarget" 7 ''
          Code generation targets keyed by name, such as `typescript` or `go`.

          Generated helpers consume resolved variables and secret metadata; they
          do not store plaintext secret values in Nix.
        '');
        groups = proto.withExample {
          dev = {
            "age-pub" = "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1";
          };
        } (proto.map "string" "SecretsGroup" 8 ''
          Deprecated legacy groups metadata.
        '');
      };
    };

    # Master key configuration
    MasterKey = proto.mkMessage {
      name = "MasterKey";
      description = "Legacy master key for `.age`/vals secret consumers";
      fields = {
        age_pub = proto.withExample "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1" (
          proto.string 1 ''
            AGE public key for encrypting legacy `.age` secrets to this key.
            Format: age1... (bech32-encoded)
          ''
        );
        ref = proto.withExample "ref+file://.stack/keys/local.txt" (
          proto.string 2 ''
            Vals reference that resolves to the AGE private key.

            `ref+file://` paths are resolved relative to the working directory
            used by the legacy consumer. External refs require the matching vals
            provider credentials at runtime.
            Examples:
              - ref+file://.stack/keys/local.txt (local file)
              - ref+awsssm://stackpanel/keys/dev (AWS SSM Parameter Store)
              - ref+vault://secret/data/stackpanel/prod#key (HashiCorp Vault)
          ''
        );
        resolve_cmd = proto.optional (
          proto.withExample "op read 'op://vault/stackpanel/age-key'" (
            proto.string 3 ''
              Custom command to resolve the private key (overrides `ref`).
              The command should output the AGE private key to stdout.
              Example: op read 'op://vault/stackpanel/age-key'
            ''
          )
        );
      };
    };
  };
}
