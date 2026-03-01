# Secrets

Auto-generated secrets documentation for **stackpanel**.

## How It Works

Secrets are stored in SOPS-encrypted YAML files, organized by **group** (e.g., `dev`, `prod`, `common`). Each group has its own AGE keypair for encryption/decryption. Variables reference their group via their ID prefix: a variable with ID `/dev/API_KEY` stores its encrypted value under the key `API_KEY` in `vars/dev.sops.yaml`.

The `common` group is special -- it is encrypted to ALL group keys, so any group member can decrypt shared secrets.

Variable values in `config.nix` are empty strings for secrets. The actual secret values live only in the SOPS files.

## Directory Structure

```
.stackpanel/secrets/
├── README.md               # This file (auto-generated)
├── vars/                    # SOPS-encrypted secret files
│   ├── dev.sops.yaml        # Dev secrets
│   ├── prod.sops.yaml       # Prod secrets
│   ├── common.sops.yaml     # Shared secrets (encrypted to all groups)
│   └── .sops.yaml           # Generated SOPS config (gitignored)
├── recipients/              # Recipient keys for team access
│   ├── groups.json          # Group membership mapping
│   ├── team/                # Default team recipient group
│   │   └── <user>.age.pub   # Team member public keys
│   └── admins/              # Admin recipient group
│       └── <user>.age.pub   # Admin public keys
├── keys/                    # Local AGE keypair (gitignored)
│   ├── local.age            # Private key
│   └── local.age.pub        # Public key
└── state/                   # Generated state (gitignored)
    └── manifest.json        # Current secrets manifest
```

## Quick Start

### 1. Join the team

On first shell entry, a local AGE key is auto-generated. Register yourself as a recipient:

```bash
secrets:join              # Join the default "team" group
secrets:join --group admins  # Join the admins group
```

After joining, commit your public key and push. A CI workflow will re-encrypt group keys for all recipients.

### 2. Set a secret

```bash
secrets:set API_KEY --group dev --value 'sk_live_xxx'
echo 'password123' | secrets:set DATABASE_URL --group prod
```

### 3. Read a secret

```bash
secrets:get API_KEY                  # Reads from dev (default)
secrets:get DATABASE_URL --group prod
```

### 4. List secrets

```bash
secrets:list           # All groups
secrets:list dev       # Only dev group
```

### 5. Load secrets into shell

```bash
eval $(secrets:load dev)              # Export as env vars
secrets:load dev --format json        # JSON output
secrets:load common --format yaml     # YAML output
```

## Groups

Groups control which AGE keypair encrypts a set of secrets.

### Configured Groups

- **dev** -- initialized
- **prod** -- initialized

### Initialize a new group

```bash
secrets:init-group <name>              # Generate keypair, store in SSM
secrets:init-group <name> --no-ssm     # Skip SSM storage
secrets:init-group <name> --dry-run    # Preview only
```

After initialization, add the group's public key to `config.nix` under `stackpanel.secrets.groups.<name>.age-pub`.

## Variable ID Convention

Variable IDs encode their group: `/<group>/<key>`

- `/dev/API_KEY` -- stored in `vars/dev.sops.yaml` under key `API_KEY`
- `/prod/DATABASE_URL` -- stored in `vars/prod.sops.yaml` under key `DATABASE_URL`
- `/common/SHARED_TOKEN` -- stored in `vars/common.sops.yaml`, encrypted to all groups

Non-secret variables use `/var/<key>` (plaintext config) or `/computed/<key>` (derived values).

## Current Secrets by Group

- **dev**: `openrouter-api-key`, `test-api-key`

## Other Commands

| Command | Description |
|---|---|
| `secrets:show-keys` | Show all configured master keys and groups |
| `secrets:rekey <id> --keys k1,k2` | Re-encrypt a secret to different keys |

## How Encryption Works

1. **SOPS** encrypts YAML files using AGE public keys from `config.nix`
2. **Decryption** uses `SOPS_AGE_KEY_CMD` which lazily resolves keys from: local key, recipient `.age` files, `.enc.age` group keys, or per-group `key-cmd`
3. **Recipients** get access when their public key is added and group keys are re-encrypted via CI
4. **No vals references** -- secret values live directly in SOPS files, not as `ref+sops://` pointers
