# StackPanel Secrets Module

Master key-based secrets management for StackPanel projects.

## Overview

This module provides a simplified secrets system using [AGE](https://github.com/FiloSottile/age) encryption with master keys. Instead of per-user keys, a few master keys encrypt all secrets, and each secret specifies which master keys can decrypt it.

## Key Concepts

### Master Keys

Master keys are the **only** keys used for encrypting/decrypting secrets:

```nix
stackpanel.secrets.master-keys = {
  # Auto-generated local key - always works
  local = {
    age-pub = "age1...";  # computed from private key
    ref = "ref+file://.stackpanel/state/keys/local.txt";
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
```

### Variable Types

Variables can be one of four types:

| Type | Description | Value Field Contains | Resolved At |
|------|-------------|---------------------|-------------|
| `LITERAL` | Plain text value | The actual value | Eval time |
| `SECRET` | Encrypted with master keys | Empty (value in .age file) | Runtime |
| `VALS` | External secret store ref | `ref+awsssm://...` | Runtime |
| `EXEC` | Shell command | Command to execute | Runtime |

### Example Configuration

```nix
{
  # Master keys
  stackpanel.secrets.master-keys = {
    local = { ... };  # auto-configured
    dev = {
      age-pub = "age1...";
      ref = "ref+awsssm://stackpanel/keys/dev";
    };
  };

  # Variables
  stackpanel.variables = {
    "/dev/postgres-url" = {
      key = "POSTGRES_URL";
      type = "LITERAL";
      value = "postgresql://localhost:5432/dev";
    };
    
    "/prod/api-key" = {
      key = "API_KEY";
      type = "SECRET";
      master-keys = [ "prod" ];  # only prod key can decrypt
    };
    
    "/shared/openai-key" = {
      key = "OPENAI_API_KEY";
      type = "SECRET";
      master-keys = [ "dev" "prod" ];  # both can decrypt
    };
    
    "/dev/git-commit" = {
      key = "GIT_COMMIT";
      type = "EXEC";
      value = "git rev-parse --short HEAD";
    };
  };
}
```

## Available Commands

| Command | Description |
|---------|-------------|
| `secrets:set <id> --keys k1,k2` | Set a secret (encrypt to master keys) |
| `secrets:get <id>` | Get a decrypted secret |
| `secrets:list` | List all encrypted secrets |
| `secrets:rekey <id> --keys k1,k2` | Re-encrypt to different master keys |
| `secrets:show-keys` | Show configured master keys |
| `secrets:export --format env|json|yaml` | Export all secrets |
| `secrets:env` | Load secrets into current shell |

## How It Works

### Encryption

When you run `secrets:set /prod/api-key --keys prod`:

1. Look up `master-keys.prod.age-pub`
2. Encrypt the value: `age -r age1... -o .stackpanel/secrets/prod-api-key.age`

For multiple keys: `age -r key1 -r key2 -o secret.age`

### Decryption

When decrypting at runtime:

1. Try each configured master key in order
2. Resolve the key using vals: `vals eval "ref+awsssm://..."`
3. Decrypt with the resolved private key
4. Return the decrypted value

### Local Development

A `local` master key is auto-generated on first shell entry:
- Private key: `.stackpanel/state/keys/local.txt`
- Public key: `.stackpanel/state/keys/local.pub`

This ensures secrets can always be created without external configuration.

## External Secret Stores

Master key private keys can be stored anywhere that vals supports:

```nix
# AWS SSM Parameter Store
ref = "ref+awsssm://stackpanel/keys/prod";

# HashiCorp Vault
ref = "ref+vault://secret/data/stackpanel/prod#key";

# GCP Secret Manager
ref = "ref+gcpsecrets://project/stackpanel-prod";

# Local file (default for local key)
ref = "ref+file://.stackpanel/state/keys/local.txt";
```

For unsupported stores, use `resolve-cmd`:

```nix
prod = {
  age-pub = "age1...";
  ref = "";  # not used
  resolve-cmd = "op read 'op://vault/stackpanel/age-key'";
};
```

## Migration from Per-User Keys

If you previously used per-user keys:

1. Add master keys to your config
2. Re-encrypt secrets: `secrets:rekey /my-secret --keys dev,prod`
3. Remove old user key references

The user model no longer includes public keys - users are just team member metadata.
