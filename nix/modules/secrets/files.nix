# Secrets module file generation
# Generates README, gitignore, placeholders, and .sops.yaml
{lib}: {
  # Placeholder content for new secrets files
  secretsPlaceholder = appName: env: ''
    # ${appName} ${env} secrets - edit with: sops secrets/${appName}/${env}.yaml
    #
    # Example structure:
    # database:
    #   password: "your-db-password"
    # api_keys:
    #   stripe: "sk_live_..."
    #
    # Local overrides: create secrets/${appName}/${env}.local.yaml (gitignored)
  '';

  # Gitignore content for secrets directory
  secretsGitignore = ''
    # Local secret overrides - never commit
    *.local.yaml

    # Decrypted secrets - never commit
    *.dec.yaml
    *.decrypted.yaml

    # Editor backups
    *~
    *.swp
  '';

  # Generate README with vals documentation if enabled
  secretsReadme = backend: ''
    # Secrets

    Encrypted with [SOPS](https://github.com/getsops/sops) + AGE.
    ${lib.optionalString (backend == "vals") ''
    Resolved with [vals](https://github.com/helmfile/vals) for multi-backend support.
    ''}

    ## Per-App Structure

    Each app has its own secrets directory:

    ```
    secrets/
    └── {appName}/
        ├── common.yaml      # Shared across all environments
        ├── dev.yaml         # Development secrets
        ├── staging.yaml     # Staging secrets
        └── prod.yaml        # Production secrets
    ```

    ## Usage

    ```bash
    # Edit secrets for an app/environment
    sops secrets/api/dev.yaml
    sops secrets/api/staging.yaml
    sops secrets/api/prod.yaml

    # Common secrets (shared across all environments)
    sops secrets/api/common.yaml
    ```
    ${lib.optionalString (backend == "vals") ''

    ## vals - Multi-Backend Secret Resolution

    vals supports multiple secret backends with a unified interface:

    ```bash
    # Resolve secrets from SOPS file
    vals eval -f secrets.template.yaml

    # Run command with secrets as environment variables
    vals exec -f secrets.template.yaml -- ./start-server.sh
    ```

    ### Supported Backends

    - **SOPS** (default): `ref+sops://secrets/api/dev.yaml#/database/password`
    - **AWS Secrets Manager**: `ref+awssecrets://my-secret#/key`
    - **AWS SSM Parameter Store**: `ref+awsssm://my-parameter`
    - **1Password**: `ref+op://vault/item/field`
    - **HashiCorp Vault**: `ref+vault://secret/data/myapp#/password`
    - **Doppler**: `ref+doppler://PROJECT/CONFIG#/SECRET`
    - **Environment Variables**: `ref+envsubst://$MY_VAR`

    ### Template Example

    Create `secrets.template.yaml`:

    ```yaml
    DATABASE_URL: ref+sops://secrets/api/dev.yaml#/database/url
    API_KEY: ref+awssecrets://myapp/api-key
    DEBUG: ref+envsubst://$DEBUG
    ```

    Then resolve:

    ```bash
    vals eval -f secrets.template.yaml > .env
    # Or run directly:
    vals exec -f secrets.template.yaml -- ./start-server.sh
    ```
    ''}

    ## Local Overrides

    Create `secrets/{app}/{env}.local.yaml` for local-only secrets (gitignored):

    ```bash
    # Copy dev secrets as a starting point
    sops -d secrets/api/dev.yaml > secrets/api/dev.local.yaml
    # Edit as needed, then encrypt
    sops -e -i secrets/api/dev.local.yaml
    ```

    ## Adding Team Members

    1. Get their AGE public key: `age-keygen -y ~/.age/key.txt`
    2. Add to `.stackpanel/secrets/users.nix`
    3. Re-encrypt secrets: `sops updatekeys secrets/api/dev.yaml`
  '';

  # Generate all files for the secrets module
  generateFiles = {
    cfg,
    toYaml,
    sopsYamlContent,
    secretsPlaceholder,
    secretsGitignore,
    secretsReadme,
  }:
    {
      # .sops.yaml - SOPS configuration at repo root
      ".sops.yaml".text = toYaml sopsYamlContent;

      # secrets/.gitignore - ignore local overrides
      "${cfg.secretsDir}/.gitignore".text = secretsGitignore;

      # secrets/README.md - usage instructions
      "${cfg.secretsDir}/README.md".text = secretsReadme cfg.backend;
    }
    // lib.optionalAttrs cfg.generatePlaceholders (
      # Generate placeholder files for each app/environment
      lib.foldl' (acc: appName: let
        appData = cfg.apps.${appName};
        envFiles = lib.mapAttrs' (env: _:
          lib.nameValuePair "${cfg.secretsDir}/${appName}/${env}.yaml"
          {text = secretsPlaceholder appName env;})
        (appData.environments or {});
        commonFile = {
          "${cfg.secretsDir}/${appName}/common.yaml".text = secretsPlaceholder appName "common";
        };
      in
        acc // envFiles // commonFile) {}
      (lib.attrNames cfg.apps)
    );
}
