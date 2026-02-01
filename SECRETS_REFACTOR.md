# Secrets Architecture Refactor: Group-Based SOPS

## Overview

This refactor changes how secrets are encrypted and stored in Stackpanel, moving from individual `.age` files to group-based SOPS YAML files with vals references.

## Problems with the Old System

### Individual .age Files (`.stackpanel/secrets/vars/*.age`)

**Issues:**
1. **No batch operations** - Each secret is a separate file, requiring individual encryption
2. **No standard tooling** - Requires custom scripts for most operations
3. **Difficult access control** - All secrets encrypted to the same recipients
4. **No key rotation support** - Can't easily rotate keys for multiple secrets
5. **Non-portable** - Paths hardcoded as `.stackpanel/secrets/vars/`

### Hardcoded Paths

The old code had vals references like:
```
ref+sops://.stackpanel/secrets/dev.yaml#/KEY
```

**Problems:**
- `.stackpanel` path is **configurable** via `stackpanel.secrets.secrets-dir`
- References break when deployed to Docker (different directory structure)
- No way to make the env package truly portable

## New Architecture: Group-Based SOPS

### Core Concepts

1. **Secrets stored in SOPS files per GROUP** - Not per environment, per access control group
2. **Groups control who can decrypt** - Each group has specific AGE recipients
3. **Vals references in variables** - Variables contain `ref+sops://...` instead of empty values
4. **Relative paths in env package** - Deployed package uses paths relative to `packages/env/data/`

### Directory Structure

**Source Project** (path configurable via Nix):
```
<secrets-dir>/                    # Default: .stackpanel/secrets (configurable)
├── groups/                       # Group-based SOPS files
│   ├── dev.yaml                 # Secrets for dev group (encrypted)
│   ├── staging.yaml             # Secrets for staging group (encrypted)
│   └── prod.yaml                # Secrets for prod group (encrypted)
├── .sops.yaml                   # SOPS config with key groups
└── vars.yaml                    # Plaintext shared config
```

**Deployed Env Package** (portable):
```
packages/env/data/
├── .sops.yaml                   # Self-contained SOPS config
├── apps/                        # Plain YAML with vals refs (NOT encrypted)
│   ├── web/
│   │   ├── dev.yaml            # { DATABASE_URL: "ref+sops://groups/dev.yaml#/..." }
│   │   └── prod.yaml
│   └── docs/
│       └── dev.yaml
└── groups/                      # SOPS-encrypted files (copied from source)
    ├── dev.yaml
    ├── staging.yaml
    └── prod.yaml
```

## Path Configuration

### Problem: Hardcoded `.stackpanel` Path

The secrets directory is **configurable** in Nix:
```nix
{
  stackpanel.secrets.secrets-dir = ".stackpanel/secrets";  # or any path
}
```

### Solution: Read from Nix Config

The Go agent now:
1. Reads `stackpanel.secrets.secrets-dir` from Nix eval
2. Constructs groups path as `<secrets-dir>/groups/`
3. Returns TWO vals references:
   - `valsRef`: Source project ref (uses configured path)
   - `envPackageRef`: Deployment ref (relative path)

### Example

**Writing a secret:**
```bash
POST /api/secrets/group/write
{
  "key": "DATABASE_URL",
  "value": "postgres://...",
  "group": "dev"
}
```

**Response:**
```json
{
  "key": "DATABASE_URL",
  "group": "dev",
  "path": ".stackpanel/secrets/groups/dev.yaml",
  "valsRef": "ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL",
  "envPackageRef": "ref+sops://groups/dev.yaml#/DATABASE_URL",
  "recipientCount": 3
}
```

**Usage:**
- Use `valsRef` in source project configs (variables.nix, apps.nix)
- Use `envPackageRef` in deployed apps (Docker, K8s)

## Reference Transformation

When generating `packages/env/data/`, the agent **transforms** vals references to be relative:

**Source (apps.nix):**
```yaml
DATABASE_URL: ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL
```

**Deployed (packages/env/data/apps/web/dev.yaml):**
```yaml
DATABASE_URL: ref+sops://groups/dev.yaml#/DATABASE_URL
```

This makes the env package **portable** - copy it to Docker and it works.

## API Endpoints

### Write Secret to Group
```
POST /api/secrets/group/write
{
  "key": "DATABASE_URL",
  "value": "postgres://user:pass@localhost:5432/db",
  "group": "dev",
  "description": "Main database connection"
}

Response:
{
  "key": "DATABASE_URL",
  "group": "dev",
  "valsRef": "ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL",
  "envPackageRef": "ref+sops://groups/dev.yaml#/DATABASE_URL"
}
```

### Read Secret from Group
```
POST /api/secrets/group/read
{
  "key": "DATABASE_URL",
  "group": "dev"
}

Response:
{
  "key": "DATABASE_URL",
  "group": "dev",
  "value": "postgres://user:pass@localhost:5432/db"
}
```

### Delete Secret from Group
```
DELETE /api/secrets/group/delete?group=dev&key=DATABASE_URL

Response:
{
  "key": "DATABASE_URL",
  "group": "dev",
  "deleted": true
}
```

### List Groups and Keys
```
GET /api/secrets/group/list

Response:
{
  "groups": {
    "dev": ["DATABASE_URL", "REDIS_URL", "API_KEY"],
    "staging": ["DATABASE_URL", "API_KEY"],
    "prod": ["DATABASE_URL", "API_KEY", "STRIPE_SECRET"]
  }
}
```

### Generate Env Package
```
POST /api/secrets/generate-env-package

Response:
{
  "path": "packages/env/data",
  "apps": 3,
  "groups": ["dev", "staging", "prod"]
}
```

## Frontend Changes

### EditSecretDialog

**New Features:**
1. **Group selector** - Choose which access control group (dev, staging, prod)
2. **Vals reference preview** - Shows what the reference will be
3. **Dual reference support** - Returns both valsRef and envPackageRef

**Usage Flow:**
1. User clicks "Edit" on a secret variable
2. Dialog shows group selector (defaults to "dev")
3. User enters the secret value
4. On save:
   - Secret written to `.stackpanel/secrets/groups/<group>.yaml`
   - Variable value becomes `valsRef` (for source project)
   - `envPackageRef` available for deployment configs

### Types

```typescript
interface GroupSecretWriteRequest {
  key: string;
  value: string;
  group: string;
  description?: string;
}

interface GroupSecretWriteResponse {
  key: string;
  group: string;
  path: string;
  valsRef: string;           // For source project
  envPackageRef: string;     // For deployment
  recipientCount: number;
}
```

## Migration from .age Files

### Step 1: Create Groups

```bash
# Initialize groups (generates keypairs, stores in SSM or local)
secrets:init-group dev
secrets:init-group staging
secrets:init-group prod
```

### Step 2: Migrate Existing Secrets

For each `.age` file in `vars/`:

```bash
# Decrypt the old secret
VALUE=$(age -d -i ~/.age/key.txt .stackpanel/secrets/vars/my-secret.age)

# Write to a group using the UI or API
curl -X POST http://localhost:3100/api/secrets/group/write \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"MY_SECRET\",\"value\":\"$VALUE\",\"group\":\"dev\"}"
```

### Step 3: Update Variable References

Replace empty values with vals references in your configs:

**Old (variables.nix):**
```nix
{
  "/my-secret" = {
    id = "/my-secret";
    key = "my-secret";
    type = "SECRET";
    value = "";  # Empty - references .age file
  };
}
```

**New (variables.nix):**
```nix
{
  "/my-secret" = {
    id = "/my-secret";
    value = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/MY_SECRET";
  };
}
```

Or use in app configs:

```nix
{
  apps.web.environments.dev.env = {
    MY_SECRET = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/MY_SECRET";
  };
}
```

### Step 4: Delete Old .age Files

```bash
rm -rf .stackpanel/secrets/vars/*.age
```

## Access Control with Groups

Groups enable fine-grained access control:

```yaml
# .stackpanel/secrets/groups/.sops.yaml
keys:
  - &alice age1alice...
  - &bob age1bob...
  - &ci age1ci...
  - &ops age1ops...

creation_rules:
  # Dev: Everyone has access
  - path_regex: ^dev\.yaml$
    key_groups:
      - age:
          - *alice
          - *bob
          - *ci

  # Staging: Ops + CI
  - path_regex: ^staging\.yaml$
    key_groups:
      - age:
          - *alice
          - *ops
          - *ci

  # Prod: Restricted
  - path_regex: ^prod\.yaml$
    key_groups:
      - age:
          - *alice
          - *ops
```

## Runtime with vals

The `vals` tool resolves references at runtime:

```bash
# Decrypt and print secrets
vals eval -f packages/env/data/apps/web/dev.yaml

# Load into environment
eval $(vals env packages/env/data/apps/web/dev.yaml)

# In a script
export DATABASE_URL=$(vals eval ref+sops://groups/dev.yaml#/DATABASE_URL)
```

## Docker Deployment

### Dockerfile
```dockerfile
FROM node:20-alpine

# Install SOPS for decryption
RUN apk add --no-cache sops

# Copy the env package (self-contained)
COPY packages/env/data /app/env

# Inject AGE key (via secret mount or env var)
ENV SOPS_AGE_KEY_FILE=/run/secrets/age-key

# App code
COPY . /app
WORKDIR /app

# At runtime, vals resolves the refs
CMD ["node", "entrypoint.js"]
```

### Entrypoint
```javascript
// entrypoint.js
import { loadAppEnv } from '@stackpanel/env/loader';

// Load secrets from the mounted env package
await loadAppEnv('web', process.env.NODE_ENV || 'prod');

// Now process.env has decrypted values
import('./server.js');
```

## Benefits

### 1. Standard Tooling
- Use `sops` CLI for all operations
- Use `vals` for runtime resolution
- Use `.sops.yaml` for key management

### 2. Batch Operations
```bash
# Edit all dev secrets at once
sops .stackpanel/secrets/groups/dev.yaml

# Rotate keys for all secrets in a group
sops updatekeys .stackpanel/secrets/groups/dev.yaml
```

### 3. Access Control
- Different keys per group
- IAM-controlled via SSM Parameter Store
- Audit who can access which groups

### 4. Portability
- Relative paths in env package
- Self-contained with `.sops.yaml`
- Works in Docker, K8s, anywhere

### 5. No Path Assumptions
- Reads `secrets-dir` from Nix config
- Returns both source and deployment refs
- Frontend doesn't need to know paths

## Best Practices

1. **Use meaningful group names** - `dev`, `staging`, `prod`, `ops`, `analytics`
2. **Minimize prod access** - Only add keys that absolutely need production secrets
3. **Rotate keys periodically** - Use `sops updatekeys` when team members change
4. **Keep refs in version control** - Vals references are NOT secrets
5. **Don't commit decrypted values** - Only commit encrypted SOPS files
6. **Use envPackageRef for deployments** - Ensures portability
7. **Let the API build refs** - Don't construct paths client-side

## Troubleshooting

### "Failed to decrypt secret"
- Check that your AGE key is available (`~/.config/age/key.txt`)
- Verify you're in the recipient list for that group's `.sops.yaml`
- Run `sops -d .stackpanel/secrets/groups/dev.yaml` to test manually

### "Invalid group name"
- Group names are sanitized (alphanumeric, hyphens, underscores)
- Initialize the group first: `secrets:init-group <name>`

### "References don't work in Docker"
- Make sure you're using `envPackageRef` (relative paths)
- Check that `packages/env/data/groups/` contains the encrypted files
- Verify SOPS AGE key is mounted/available in container

### "Path not found"
- The `secrets-dir` might be customized in your Nix config
- Check `stackpanel.secrets.secrets-dir` in your config
- Use the `valsRef` returned by the API, don't construct it manually

## Summary

**Old System:**
- Individual `.age` files per secret
- Hardcoded `.stackpanel/secrets/vars/` path
- Empty variable values, implicit file lookup
- Non-portable

**New System:**
- Group-based SOPS YAML files
- Configurable paths read from Nix
- Vals references in variables (explicit)
- Portable env package with relative refs
- Standard tooling (sops, vals)
- Fine-grained access control

The refactor makes secrets management **portable**, **standard**, and **secure**.