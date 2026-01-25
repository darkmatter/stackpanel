# @stackpanel/env

Self-contained, portable environment variable management for Stackpanel apps.

## Structure

```
packages/env/
├── data/                          # SOPS-encrypted secrets (portable)
│   ├── .sops.yaml                 # Self-contained SOPS config
│   ├── shared/
│   │   └── vars.yaml              # Plaintext shared config
│   ├── web/
│   │   ├── dev.yaml               # Web app dev secrets
│   │   ├── staging.yaml           # Web app staging secrets
│   │   └── prod.yaml              # Web app prod secrets
│   └── <app>/
│       └── <env>.yaml
├── src/
│   ├── index.ts                   # Main exports
│   ├── loader.ts                  # Runtime SOPS decryption
│   ├── web.ts                     # Web app env schema
│   └── generated/                 # Auto-generated znv modules
│       ├── index.ts
│       └── <app>/
│           ├── index.ts
│           └── <env>.ts
└── package.json
```

## Usage

### Development (with devshell)

In development, secrets are typically injected by the devshell or process-compose:

```typescript
import { env } from '@stackpanel/env/web';
console.log(env.POSTGRES_URL);
```

### Production / Docker

For production or Docker, use the loader to decrypt secrets at runtime:

```typescript
import { loadAppEnv } from '@stackpanel/env/loader';

// Load and inject into process.env
await loadAppEnv('web', 'prod');

// Then use normally
import { env } from '@stackpanel/env/web';
console.log(env.POSTGRES_URL);
```

### Docker Setup

1. Install SOPS in your Docker image:
   ```dockerfile
   RUN apk add --no-cache sops
   # or
   RUN apt-get install -y sops
   ```

2. Mount or copy the AGE key:
   ```dockerfile
   # Option 1: Mount key file
   ENV SOPS_AGE_KEY_FILE=/run/secrets/age-key
   
   # Option 2: Inject key via env var
   ENV SOPS_AGE_KEY=AGE-SECRET-KEY-1...
   ```

3. Copy the data directory:
   ```dockerfile
   COPY packages/env/data /app/packages/env/data
   ```

4. Load secrets in your entrypoint:
   ```typescript
   // entrypoint.ts
   import { loadAppEnv } from '@stackpanel/env/loader';
   await loadAppEnv('web', process.env.NODE_ENV || 'prod');
   
   // Now start your app
   import './server';
   ```

## Managing Secrets

### Edit secrets

```bash
# Navigate to the data directory
cd packages/env/data

# Edit a secret file (SOPS will decrypt/encrypt automatically)
sops web/dev.yaml
```

### Add new secrets

1. Add the key to the YAML file:
   ```bash
   sops web/dev.yaml
   # Add: NEW_SECRET: your-secret-value
   ```

2. Update the TypeScript schema (if not auto-generated):
   ```typescript
   // src/web.ts
   export const env = parseEnv(process.env, {
     // ... existing fields
     NEW_SECRET: z.string(),
   });
   ```

### Shared (plaintext) config

For non-sensitive config shared across apps:

```yaml
# data/shared/vars.yaml (NOT encrypted)
LOG_LEVEL: info
API_VERSION: v1
```

```typescript
import { loadSharedVars } from '@stackpanel/env/loader';
await loadSharedVars();
```

## Key Management

Keys are defined in `data/.sops.yaml`:

```yaml
keys:
  - &master age1...  # Project master key
  - &alice age1...   # Team member key

creation_rules:
  - path_regex: .*/prod\.yaml$
    key_groups:
      - age:
          - *master
          # Only specific members for prod
```

To add a new team member:
1. Get their AGE public key
2. Add it to `.sops.yaml`
3. Re-encrypt existing files: `sops updatekeys web/dev.yaml`

## Portability

This package is designed to be self-contained:

- All SOPS config is in `data/.sops.yaml` (no dependency on `.stackpanel/`)
- Secrets are stored in `data/<app>/<env>.yaml`
- Works in Docker with just SOPS + AGE key
- No relative path assumptions to repo root
