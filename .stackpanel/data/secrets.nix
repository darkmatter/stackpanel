# secrets.nix - Secrets management configuration
# type: stackpanel.secrets
# See: https://stackpanel.dev/docs/secrets
{
  # Enable secrets management
  enable = true;

  # Directory where SOPS-encrypted secrets are stored (legacy)
  input-directory = ".stackpanel/secrets";

  # Directory for individual secret .age files
  secrets-dir = ".stackpanel/secrets/vars";

  # System-level AGE public keys (CI, deploy servers, etc.)
  # These keys can decrypt all secrets regardless of environment restrictions
  system-keys = [
    # Add your CI/CD and deploy server keys here:
    # "age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3290gq"
  ];

  # Environment-specific secrets configurations
  environments = {
    # dev = {
    #   name = "dev";
    #   public-keys = [ ];
    #   sources = [ "dev" ];
    # };
    # staging = {
    #   name = "staging";
    #   public-keys = [ ];
    #   sources = [ "staging" ];
    # };
    # prod = {
    #   name = "prod";
    #   public-keys = [ ];
    #   sources = [ "prod" ];
    # };
  };

  # Code generation settings
  # Note: directory is ignored - types are always generated to packages/env/src/generated/
  codegen = {
    typescript = {
      name = "env";
      directory = "packages/env/src/generated";
      language = "CODEGEN_LANGUAGE_TYPESCRIPT";
    };
  };
}
