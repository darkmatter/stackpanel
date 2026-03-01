# Env Package Architecture

This document describes the secrets architecture used by `@gen/env`.

## Overview

Secrets are managed using a **group-based direct SOPS** approach where:

1. **Secrets are stored in SOPS-encrypted YAML files per GROUP** (e.g., `dev.sops.yaml`, `prod.sops.yaml`)
2. **Groups control access** -- each group has its own AGE keypair
3. **Variable IDs encode the group** -- a variable with ID `/dev/DATABASE_URL` stores its value in `vars/dev.sops.yaml`
4. **Variable values are empty strings** -- the actual secret value lives only in the SOPS file
5. **No vals references** -- decryption uses `sops decrypt` directly, not `ref+sops://` indirection

## Directory Structure

**Source Project** (path configurable via `stackpanel.secrets.secrets-dir`):
```
.stackpanel/secrets/
├── vars/                     # SOPS-encrypted secrets by group
│   ├── .sops.yaml           # Per-group creation rules (generated, gitignored)
│   ├── common.sops.yaml     # Shared config (encrypted to all group keys)
│   ├── dev.sops.yaml        # Dev secrets
│   ├── staging.sops.yaml    # Staging secrets
│   └── prod.sops.yaml       # Prod secrets
├── recipients/               # Recipient keys for team access
│   ├── .sops.yaml           # For .enc.age files (generated, gitignored)
│   ├── groups.json          # Recipient group -> vars file mapping
│   ├── team/                # Default team recipient group
│   │   └── <user>.age.pub   # Team member public keys
│   └── admins/              # Admin recipient group
├── keys/                     # Local AGE keypair (gitignored)
└── state/                    # Generated state (gitignored)
    └── manifest.json        # Current secrets manifest
```

## How It Works

### 1. Writing a Secret

When you set a secret via CLI or UI:

```bash
secrets:set DATABASE_URL --group dev --value "postgres://..."
```

The agent:
1. Resolves the SOPS file path: `vars/dev.sops.yaml`
2. Uses `sops set` to write the key in-place (non-destructive, preserves other keys)
3. The variable in `config.nix` has `value = ""` -- the actual value is only in the SOPS file

### 2. Variable ID Convention

Variable IDs encode the group: `/<group>/<key>`

| Variable ID | Group | SOPS File | Key in File |
|---|---|---|---|
| `/dev/database-url` | `dev` | `vars/dev.sops.yaml` | `database-url` |
| `/prod/api-key` | `prod` | `vars/prod.sops.yaml` | `api-key` |
| `/common/log-level` | `common` | `vars/common.sops.yaml` | `log-level` |
| `/var/app-name` | `var` | N/A (not encrypted) | Literal value |
| `/computed/services/postgres-port` | `computed` | N/A (computed) | Computed value |

### 3. Runtime Resolution

At runtime, secrets are decrypted directly from SOPS files:

```bash
# Decrypt all secrets in a group
sops decrypt vars/dev.sops.yaml

# Export as environment variables
eval $(secrets:load dev)

# Get a single secret
secrets:get DATABASE_URL --group dev
```

The agent uses `SOPS_AGE_KEY_CMD` to lazily resolve decryption keys from:
1. Local AGE key (`.stackpanel/state/keys/local.txt`)
2. Plaintext group keys (`recipients/<group>.age`, gitignored)
3. SOPS-encrypted group keys (`recipients/<group>.enc.age`)
4. Per-group key-cmd fallback

## Access Control

Groups enable fine-grained access control via `.sops.yaml` creation rules (auto-generated from `config.nix`):

```yaml
# .stackpanel/secrets/vars/.sops.yaml
creation_rules:
  - path_regex: ^dev\.sops\.yaml$
    key_groups:
      - age:
          - age1...  # dev group public key

  - path_regex: ^prod\.sops\.yaml$
    key_groups:
      - age:
          - age1...  # prod group public key

  - path_regex: ^common\.sops\.yaml$
    key_groups:
      - age:
          - age1...  # dev key
          - age1...  # prod key (all groups can decrypt common)
```

## Infrastructure Output Integration

The infra module system can write outputs (e.g., Neon database URL) directly to SOPS group files:

```nix
stackpanel.infra.storage-backend = {
  type = "sops";
  sops.group = "dev";  # writes to vars/dev.sops.yaml
};
```

The `Infra.syncAll()` method uses `sops set` per key for non-destructive updates that preserve existing secrets in the file.

## API Endpoints

### Write Secret to Group
```
POST /api/secrets/group/write
{
  "key": "DATABASE_URL",
  "value": "postgres://...",
  "group": "dev"
}
Response: { "success": true }
```

### Read Secret from Group
```
POST /api/secrets/group/read
{ "key": "DATABASE_URL", "group": "dev" }
Response: { "value": "postgres://..." }
```

### List Groups
```
GET /api/secrets/group/list
Response: { "groups": { "dev": ["DATABASE_URL", "REDIS_URL"], "prod": ["API_KEY"] } }
```

## Best Practices

1. **Use meaningful group names** -- `dev`, `staging`, `prod`, `ops`, `analytics`
2. **Minimize prod access** -- Only add keys that need production access
3. **Rotate keys periodically** -- Use `sops updatekeys` when team changes
4. **Don't commit decrypted values** -- Only encrypted SOPS files
5. **Use `common` for shared config** -- Encrypted to all groups, accessible by anyone with any group key
