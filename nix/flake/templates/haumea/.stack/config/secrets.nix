# ==============================================================================
# secrets.nix
#
# Secrets - SOPS-based secrets management with AGE encryption.
# See: https://stackpanel.dev/docs/secrets
#
# On first shell entry with secrets enabled:
#   - A local AGE key is auto-generated in .stack/keys/
#   - keys/.sops.yaml is configured to encrypt group keys to your local key
#
# To set up a secrets group:
#   secrets:init-group dev     # generates AGE keypair, encrypts to .enc.age
#   # Then add the public key here:
#   #   groups.dev.age-pub = "age1...";
#
# No AWS/KMS required by default. Add KMS later for team/CI access.
# ==============================================================================
{
  # enable = true;
  # secrets-dir = ".stack/secrets";
  #
  # Groups define access control boundaries
  # Each group has its own AGE keypair
  # groups = {
  #   dev = {};   # Initialize with: secrets:init-group dev
  #   prod = {};  # Initialize with: secrets:init-group prod
  # };
  #
  # Code generation for type-safe env access
  # codegen = {
  #   typescript = {
  #     name = "env";
  #     directory = "packages/gen/env/src";
  #     language = "CODEGEN_LANGUAGE_TYPESCRIPT";
  #   };
  # };
}
