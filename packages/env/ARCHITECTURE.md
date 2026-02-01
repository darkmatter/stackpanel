# Env Package Architecture

This document describes the group-based secrets architecture used by `@stackpanel/env`.

## Overview

Secrets are managed using a **group-based SOPS** approach where:

1. **Secrets are stored in SOPS-encrypted YAML files per GROUP** (not per environment)
2. **Groups control access** - each group can have different AGE recipients
3. **Variables contain vals references** - app configs use `ref+sops://...` references
4. **No decryption needed to render files** - just copy the references and encrypted files

## Key Design Decision: Relative Paths

**All vals references in the deployed env package use RELATIVE paths.**

This is critical for portability:
- Source project: `ref+sops://.stackpanel/secrets/groups/dev.yaml#/KEY` (configurable path)
- Env package: `ref+sops://groups/dev.yaml#/KEY` (relative to data dir)

The `.stackpanel` path is **configurable** via `stackpanel.secrets.secrets-dir` in Nix config.
The env package generator **transforms** source refs to relative refs during generation.

## Directory Structure

**Source Project** (path configurable via `stackpanel.secrets.secrets-dir`):
```
.stackpanel/secrets/          # Or custom path from config
├── groups/                   # SOPS-encrypted secrets by access control group
│   ├── dev.yaml             # Secrets accessible to dev group
│   ├── staging.yaml         # Secrets accessible to staging group
│   └── prod.yaml            # Secrets accessible to prod group
├── .sops.yaml               # SOPS config defining key groups
└── vars.yaml                # Plaintext shared configuration
```

**Deployed Env Package** (portable, relative paths):
```
packages/env/data/
├── .sops.yaml               # Self-contained SOPS config
├── apps/                    # Plain YAML with RELATIVE vals references (NOT encrypted)
│   ├── web/
│   │   ├── dev.yaml         # { DATABASE_URL: "ref+sops://groups/dev.yaml#/DATABASE_URL" }
│   │   ├── staging.yaml
│   │   └── prod.yaml
│   └── docs/
│       ├── dev.yaml
│       └── prod.yaml
└── groups/                  # SOPS-encrypted files (copied)
    ├── dev.yaml
    ├── staging.yaml
    └── prod.yaml
```

**Note:** The apps/*.yaml files use `ref+sops://groups/...` (relative to data dir),
NOT `ref+sops://.stackpanel/secrets/groups/...` (source project path).

## How It Works

### 1. Writing a Secret

When you edit a secret in the UI:

```
User enters: DATABASE_URL = "postgres://..."
Selected group: dev
```

The agent:
1. Reads existing `.stackpanel/secrets/groups/dev.yaml` (or creates new)
2. Adds/updates the key with the plaintext value
3. Encrypts with SOPS using the group's AGE recipients
4. Returns a vals reference: `ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL`

### 2. Using in App Config

The app's environment config contains vals references (NOT actual secrets).

**In source project** (references the configured secrets-dir):
```yaml
# From apps.nix or variables.nix
DATABASE_URL: ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL
```

**In deployed env package** (relative paths):
```yaml
# packages/env/data/apps/web/dev.yaml
DATABASE_URL: ref+sops://groups/dev.yaml#/DATABASE_URL
REDIS_URL: ref+sops://groups/dev.yaml#/REDIS_URL
API_KEY: ref+sops://groups/prod.yaml#/API_KEY
```

The generator **transforms** source refs to relative refs automatically.

### 3. Runtime Resolution

At runtime, [vals](https://github.com/helmfile/vals) resolves the references:

```bash
# vals evaluates the references
vals eval -f packages/env/data/apps/web/dev.yaml
# Output:
# DATABASE_URL: postgres://user:pass@localhost:5432/dev
# REDIS_URL: redis://localhost:6379
# API_KEY: sk_live_xxx
```

## Access Control

Groups enable fine-grained access control:

```yaml
# .stackpanel/secrets/.sops.yaml
keys:
  - &alice age1alice...
  - &bob age1bob...
  - &ci age1ci...
  - &prod-only age1prod...

creation_rules:
  # Dev: everyone
  - path_regex: ^groups/dev\.yaml$
    key_groups:
      - age:
          - *alice
          - *bob
          - *ci

  # Staging: ops team + CI
  - path_regex: ^groups/staging\.yaml$
    key_groups:
      - age:
          - *alice
          - *ci

  # Prod: restricted
  - path_regex: ^groups/prod\.yaml$
    key_groups:
      - age:
          - *alice
          - *prod-only
```

## Generating the Env Package

Run `secrets:generate-env-package` (or use the API endpoint) to:

1. Copy group SOPS files to `packages/env/data/groups/`
2. Generate app env YAML files with vals references
3. Generate `.sops.yaml` for self-contained decryption

The resulting `packages/env/data/` directory is **portable** - copy it to Docker and it works with just SOPS + AGE key.

## Migration from .age Files

The old architecture used individual `.age` files per secret:

```
.stackpanel/secrets/vars/
├── database-url.age
├── api-key.age
└── stripe-secret.age
```

**Problems with .age files:**
- No batch operations
- No built-in key rotation
- Harder to manage access control
- Requires custom tooling

**New group-based approach:**
- Standard SOPS tooling (`sops`, `vals`)
- Batch encrypt/decrypt per group
- Access control via `.sops.yaml` creation rules
- Easy key rotation with `sops updatekeys`

### Migration Steps

1. Create groups: `secrets:init-group dev && secrets:init-group prod`
2. For each secret in `vars/*.age`:
   - Decrypt: `age -d -i ~/.age/key.txt vars/my-secret.age`
   - Write to group: `sops set groups/dev.yaml /MY_SECRET "value"`
3. Update app configs to use vals references
4. Delete old `.age` files

## API Endpoints

### Write Secret to Group
```
POST /api/secrets/group/write
{
  "key": "DATABASE_URL",
  "value": "postgres://...",
  "group": "dev"
}
Response: {
  "valsRef": "ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL",
  "envPackageRef": "ref+sops://groups/dev.yaml#/DATABASE_URL"
}
```

- `valsRef`: Use in source project configs (uses configured secrets-dir)
- `envPackageRef`: Use in deployed apps (relative path, portable)

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

### Generate Env Package
```
POST /api/secrets/generate-env-package
Response: { "path": "packages/env/data", "apps": 3, "groups": ["dev", "prod"] }
```

## Best Practices

1. **Use meaningful group names** - `dev`, `staging`, `prod`, `ops`, `analytics`
2. **Minimize prod access** - Only add keys that need production access
3. **Rotate keys periodically** - Use `sops updatekeys` when team changes
4. **Keep refs in version control** - The vals references are NOT secrets
5. **Don't commit decrypted values** - Only encrypted SOPS files
6. **Don't hardcode paths** - The secrets-dir is configurable; always use API-returned refs
7. **Use envPackageRef for deployments** - Relative paths ensure portability to Docker/K8s

## Path Resolution

| Context | Reference Format | Example |
|---------|-----------------|---------|
| Source project | Full path from config | `ref+sops://.stackpanel/secrets/groups/dev.yaml#/KEY` |
| Env package | Relative to data dir | `ref+sops://groups/dev.yaml#/KEY` |
| Docker | Relative (mount data dir) | `ref+sops://groups/dev.yaml#/KEY` |

The key insight is that **vals resolves paths relative to the current working directory**.
In Docker, you either:
1. Mount `packages/env/data/` and run from there, OR
2. Set `SOPS_FILE` env var to point to the groups directory