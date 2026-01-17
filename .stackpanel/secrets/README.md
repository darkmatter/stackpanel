# Stackpanel Secrets Configuration

Configuration files for the stackpanel secrets module with agenix integration.

## Directory Structure

```
.stackpanel/secrets/
├── secrets.nix          # Agenix secrets definition (auto-generated)
├── config.nix           # Global settings
├── users.nix            # Team members (legacy, prefer .stackpanel/data/users.nix)
├── vars/                # Individual secret .age files
│   ├── database-url.age
│   └── api-key.age
└── apps/
    ├── _example/        # Example app (ignored by module)
    └── {appName}/
        ├── config.nix   # App codegen settings
        ├── common.nix   # Shared schema across all environments
        ├── dev.nix      # Dev-specific schema + access control
        ├── dev.yaml     # Combined encrypted secrets for dev
        ├── staging.nix  # Staging-specific schema + access control
        ├── staging.yaml # Combined encrypted secrets for staging
        ├── prod.nix     # Production-specific schema + access control
        └── prod.yaml    # Combined encrypted secrets for prod
```

## How It Works

### Individual Secrets (vars/)

Each secret is stored as an individual `.age` file in the `vars/` directory:

```
vars/
├── database-url.age     # Encrypted DATABASE_URL
├── api-key.age          # Encrypted API_KEY
└── stripe-secret.age    # Encrypted STRIPE_SECRET
```

These are encrypted using [age](https://github.com/FiloSottile/age) and managed via:
- The StackPanel UI
- API endpoint: `POST /api/secrets/write`
- CLI: `age -e -r <recipient> -o vars/my-secret.age`

### Combined Secrets (apps/{appName}/{env}.yaml)

For each app environment, individual secrets are combined into a single encrypted YAML:

```yaml
# Decrypted view of apps/myapp/dev.yaml
DATABASE_URL: |
  postgres://user:pass@localhost:5432/mydb
API_KEY: |
  sk_test_abc123
```

This combined format is what applications load at runtime via SOPS or vals.

### secrets.nix (Agenix)

The `secrets.nix` file tells agenix which public keys can decrypt each secret:

```nix
let
  allKeys = [
    "age1..."  # Alice
    "age1..."  # Bob
    "age1..."  # CI system
  ];
in
{
  "vars/database-url.age".publicKeys = allKeys;
  "vars/api-key.age".publicKeys = allKeys;
}
```

This file is auto-generated. Regenerate it with:

```bash
nix eval --raw .#stackpanelFullConfig.secrets.secrets-nix-content > .stackpanel/secrets/secrets.nix
```

## Getting Started

### 1. Configure Users

Edit `.stackpanel/data/users.nix`:

```nix
{
  alice = {
    name = "Alice";
    github = "alice";
    public-keys = [
      "age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3290gq"
    ];
    secrets-allowed-environments = [ "dev" "staging" "prod" ];  # or [] for all
  };
  
  bob = {
    name = "Bob";
    github = "bobdev";
    public-keys = [
      "age1..."
    ];
    secrets-allowed-environments = [ "dev" "staging" ];  # No prod access
  };
}
```

### 2. Add System Keys (Optional)

Configure CI/deploy server keys in your Nix config:

```nix
{
  stackpanel.secrets = {
    enable = true;
    system-keys = [
      "age1..."  # CI system
      "age1..."  # Deploy server
    ];
  };
}
```

### 3. Write Secrets

Via API:

```bash
curl -X POST http://localhost:3100/api/secrets/write \
  -H "Content-Type: application/json" \
  -d '{
    "id": "database-url",
    "key": "DATABASE_URL",
    "value": "postgres://...",
    "environments": ["dev", "staging"]
  }'
```

Via CLI (direct age encryption):

```bash
echo "postgres://..." | age -e -r "age1..." -o vars/database-url.age
```

### 4. Generate Combined Secrets

For each app environment:

```bash
combine-app-secrets . myapp dev
combine-app-secrets . myapp staging
combine-app-secrets . myapp prod
```

Or regenerate all:

```bash
regenerate-all-secrets .
```

### 5. Decrypt for Use

```bash
# YAML format
decrypt-app-secrets apps/myapp/dev.yaml

# JSON format
decrypt-app-secrets apps/myapp/dev.yaml json

# Env format (KEY=value)
decrypt-app-secrets apps/myapp/dev.yaml env
```

## Creating an App

### 1. Create App Directory

```bash
mkdir -p apps/myapp
```

### 2. Create config.nix

```nix
# apps/myapp/config.nix
{
  codegen = {
    language = "typescript";  # "typescript" | "go" | null
    path = "packages/api/src/env.ts";
  };
}
```

### 3. Create common.nix (Shared Schema)

```nix
# apps/myapp/common.nix
{
  DATABASE_URL = {
    required = true;
    sensitive = true;
    description = "PostgreSQL connection string";
  };

  LOG_LEVEL = {
    required = false;
    sensitive = false;
    default = "info";
  };
}
```

### 4. Create Environment Configs

```nix
# apps/myapp/dev.nix
{
  schema = {
    DEBUG = {
      required = false;
      sensitive = false;
      default = "true";
    };
    LOG_LEVEL = {
      default = "debug";  # Override common
    };
  };

  # Users who can access dev secrets
  users = [ "alice" "bob" "charlie" ];

  # Additional AGE keys
  extraKeys = [ ];
}
```

```nix
# apps/myapp/prod.nix
{
  schema = {
    SENTRY_DSN = {
      required = true;
      sensitive = true;
    };
  };

  # Restrict prod access
  users = [ "alice" ];  # Only admin

  extraKeys = [
    "age1..."  # CI system for deploys
  ];
}
```

## Agenix / Agenix-Rekey Integration

This module integrates with:
- [agenix](https://github.com/ryantm/agenix) - Age-encrypted secrets for NixOS
- [agenix-rekey](https://github.com/oddlama/agenix-rekey) - Automatic rekeying with YubiKey support

### Using with Agenix

The generated `secrets.nix` is compatible with the agenix CLI:

```bash
# Edit a secret (opens in $EDITOR)
agenix -e vars/database-url.age

# Rekey all secrets (after changing recipients)
agenix -r
```

### Using with Agenix-Rekey

For YubiKey or FIDO2 key support, configure agenix-rekey in your flake:

```nix
{
  inputs.agenix-rekey.url = "github:oddlama/agenix-rekey";

  # In your NixOS config:
  age.rekey = {
    hostPubkey = "ssh-ed25519 AAAAC3...";
    masterIdentities = [ ./yubikey-identity.pub ];
    storageMode = "local";
    localStorageDir = ./. + "/secrets/rekeyed/${config.networking.hostName}";
  };
}
```

## vals Integration

StackPanel uses [vals](https://github.com/helmfile/vals) for secret resolution at runtime,
which supports multiple backends:

- **SOPS** (default) - `ref+sops://secrets/api/dev.yaml#/database/password`
- **Age files** - Direct age-encrypted files
- **AWS Secrets Manager** - `ref+awssecrets://my-secret`
- **1Password** - `ref+op://vault/item/field`
- **HashiCorp Vault** - `ref+vault://secret/data/myapp#/password`

## Commands

Available in the devshell:

| Command | Description |
|---------|-------------|
| `secrets:write` | Info about writing secrets via API |
| `secrets:list` | List all .age files in vars/ |
| `secrets:regenerate-nix` | Regenerate secrets.nix from config |
| `secrets:combine` | Combine secrets for an app environment |
| `secrets:decrypt` | Decrypt combined secrets |
| `secrets:regenerate-all` | Regenerate combined secrets for all apps |

## Security Considerations

1. **Never commit plaintext secrets** - Only `.age` encrypted files should be in git
2. **Limit prod access** - Use `secrets-allowed-environments` to restrict who can access production secrets
3. **Rotate secrets regularly** - Rekey when team members leave or keys are compromised
4. **Use hardware keys** - Consider YubiKey/FIDO2 for master identities via agenix-rekey
5. **Audit access** - Review users.nix periodically to ensure correct access levels