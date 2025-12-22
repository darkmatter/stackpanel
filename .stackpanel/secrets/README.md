# Stackpanel Secrets Configuration

Configuration files for the stackpanel secrets module.

## Directory Structure

```
.stackpanel/secrets/
├── config.yaml          # Global settings (backend, secretsDir)
├── users.yaml           # Team members and AGE keys
└── apps/
    ├── _example/        # Example app (ignored by module)
    └── {appName}/
        ├── config.yaml  # App codegen settings (language, path)
        ├── common.yaml  # Shared schema across all environments
        ├── dev.yaml     # Dev-specific schema + access control
        ├── staging.yaml # Staging-specific schema + access control
        └── prod.yaml    # Production-specific schema + access control
```

## Getting Started

1. Copy example files:
   ```bash
   cp config.example.yaml config.yaml
   cp users.example.yaml users.yaml
   cp -r apps/_example apps/myapp
   ```

2. Edit `users.yaml` with your team's AGE public keys

3. Edit `apps/myapp/config.yaml` for your app's codegen settings

4. Define your secrets schema in `apps/myapp/common.yaml`

5. Configure per-environment access in `dev.yaml`, `staging.yaml`, `prod.yaml`

## IDE Support

When using the VS Code workspace (`.stackpanel/gen/ide/vscode/stackpanel.code-workspace`),
you'll get intellisense and validation for all YAML files automatically.

**Required extension:** [Red Hat YAML](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)

## Schema Files

JSON Schema files for validation are in `.stackpanel/gen/schemas/secrets/`:

| Schema | Used For |
|--------|----------|
| `config.schema.json` | `config.yaml` |
| `users.schema.json` | `users.yaml` |
| `app-config.schema.json` | `apps/*/config.yaml` |
| `schema.schema.json` | `apps/*/common.yaml` |
| `env.schema.json` | `apps/*/{dev,staging,prod}.yaml` |

## How It Works

1. **Apps**: Each app has its own secrets and codegen config
2. **Common**: Shared schema inherited by all environments
3. **Environments**: Override/extend common schema, plus access control
4. **Codegen**: Each app generates typed env access for its language

### Adding a Team Member

Edit `users.yaml`:

```yaml
# Team members with access to secrets
alice:
  pubkey: "age1abc123..."
  github: alice
  admin: true  # Admins can decrypt all secrets

bob:
  pubkey: "age1xyz789..."
  github: bobdev
```

### Creating an App

Create `apps/{appName}/config.yaml`:

```yaml
codegen:
  language: typescript  # "typescript" | "python" | "go" | null
  path: packages/api/src/env.ts
```

Create `apps/{appName}/common.yaml` (shared schema):

```yaml
# Schema shared across all environments
DATABASE_URL:
  required: true
  sensitive: true
  description: PostgreSQL connection string

LOG_LEVEL:
  required: false
  sensitive: false
  default: info
```

Create `apps/{appName}/dev.yaml`:

```yaml
# Schema additions/overrides for dev
schema:
  DEBUG:
    required: false
    sensitive: false
  # Override common value
  LOG_LEVEL:
    default: debug

# Who can access dev secrets
users:
  - alice
  - bob
  - charlie

extraKeys: []
```

Create `apps/{appName}/prod.yaml`:

```yaml
schema:
  SENTRY_DSN:
    required: true
    sensitive: true

users:
  - alice  # Only admin for prod

extraKeys:
  - age1ci...  # CI system
```

## vals Integration

StackPanel uses [vals](https://github.com/helmfile/vals) for secret resolution,
which supports multiple backends:

- **SOPS** (default) - `ref+sops://secrets/api/dev.yaml#/database/password`
- **AWS Secrets Manager** - `ref+awssecrets://my-secret`
- **1Password** - `ref+op://vault/item/field`
- **HashiCorp Vault** - `ref+vault://secret/data/myapp#/password`
- **Doppler** - `ref+doppler://MYPROJECT/MYCONFIG#/MY_SECRET`

vals is backwards-compatible with SOPS-encrypted files, so existing workflows
continue to work.

## Generated Files

The module generates:

- `.sops.yaml` - SOPS configuration with rules for each app/env
- `secrets/{app}/common.yaml` - Common secrets placeholder
- `secrets/{app}/{env}.yaml` - Per-environment secrets placeholder
- `{codegen.path}` - Type-safe env access for each app
