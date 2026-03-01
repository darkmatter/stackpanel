# How to Use Group-Based Secrets

## Quick Start

Group-based secrets provide fine-grained access control for your sensitive data. Instead of encrypting all secrets to the same recipients, you can organize them into **groups** with different access levels.

## Creating a New Secret

### Via UI (Recommended)

1. Open the **Variables** panel in Stackpanel Studio
2. Click **"Add Variable"**
3. Select **"Secret"** as the type
4. **Choose a group** from the dropdown (dev, staging, prod)
5. Enter your secret name and value
6. Click **"Add Secret"**

The secret is now encrypted to the selected group's SOPS file.

### What Happens Behind the Scenes

When you create a secret:
1. The value is written to `.stackpanel/secrets/vars/<group>.sops.yaml` using `sops set` (in-place, non-destructive)
2. A variable entry is created with an empty value and a keygroup-based ID (e.g., `/dev/MY_KEY`)
3. The variable ID encodes the group and key: `/<group>/<key>`

The actual secret value lives **only** in the SOPS file. The variable's `value` field in config is an empty string for all secrets.

### Via CLI

```bash
# Set a secret in the dev group
secrets:set MY_API_KEY --group dev --value "sk-abc123"

# Set from stdin (for piping)
echo "password123" | secrets:set DATABASE_URL --group prod
```

## Editing an Existing Secret

1. Find the secret in the Variables panel
2. Click **"Edit"** 
3. You'll see the **group selector** -- you can change which group it belongs to
4. Update the value
5. Click **"Save Changes"**

The secret will be re-encrypted to the new group's recipients if you changed groups.

## Understanding Groups

### What is a Group?

A group is an **access control boundary**. Each group has:
- Its own SOPS-encrypted YAML file (`vars/<group>.sops.yaml`)
- Its own AGE keypair (public key in `config.nix`, private key in `.enc.age`)
- Separate encryption -- only holders of that group's private key can decrypt

### Default Groups

- **dev** -- For development secrets, typically accessible by all team members
- **staging** -- For staging environment, may have restricted access
- **prod** -- For production secrets, highly restricted access
- **common** -- Shared config encrypted to ALL group keys (anyone with any group key can decrypt)

### Group Access Control

Access to each group is controlled by the `.sops.yaml` configuration (auto-generated from `config.nix`):

```yaml
# .stackpanel/secrets/vars/.sops.yaml (generated, gitignored)
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
          - age1...  # prod key (encrypted to ALL group keys)
```

## Using Secrets in Apps

### In App Environments

Secrets are referenced by their variable ID, which encodes the group:

```nix
# .stackpanel/config.nix
stackpanel.variables = {
  "/dev/database-url" = {
    key = "DATABASE_URL";
    value = "";  # actual value in vars/dev.sops.yaml
  };

  "/prod/database-url" = {
    key = "DATABASE_URL";
    value = "";  # actual value in vars/prod.sops.yaml
  };
};
```

### At Runtime

Use the `secrets:load` command to decrypt and export secrets:

```bash
# Export as environment variables
eval $(secrets:load dev)

# JSON output
secrets:load dev --format json

# YAML output
secrets:load common --format yaml

# Get a single secret
secrets:get DATABASE_URL --group dev
```

## Best Practices

### 1. Choose the Right Group

- **dev** -- Non-production data, test API keys, local database URLs
- **staging** -- Pre-production data that mirrors prod structure
- **prod** -- Production credentials, live API keys, customer data
- **common** -- Shared non-sensitive config (log levels, feature flags)

### 2. Minimize Prod Access

Only add AGE keys to the prod group for:
- Ops team leads
- CI/CD systems
- On-call engineers (if needed)

### 3. Use Descriptive Key Names

Instead of:
```
/dev/my-secret
```

Use:
```
/dev/stripe-api-key
/prod/postgres-url
```

## Common Workflows

### Sharing Secrets Across Apps

Since secrets are stored per-group (not per-app), all apps that need `DATABASE_URL` from the dev group simply reference it:

```nix
apps.web.environments.dev.env.DATABASE_URL = "";   # loaded from /dev/database-url
apps.api.environments.dev.env.DATABASE_URL = "";   # same secret, same group
```

### Promoting Secrets from Dev to Prod

1. In the UI, create the secret in the **dev** group
2. Test it works in development
3. Create a **new secret** in the **prod** group with the production value
4. The variable system automatically routes to the correct SOPS file based on the ID prefix

**Don't** move the same secret value from dev to prod -- use different credentials per environment!

### Rotating a Secret

1. Generate the new credential value
2. Update via CLI: `secrets:set MY_KEY --group dev --value "new-value"`
3. Or edit in the UI
4. Deploy your apps to pick up the new value

## Infrastructure Outputs to Secrets

When using the Alchemy infrastructure module (e.g., deploying a Neon database), outputs can be automatically written to SOPS group files:

```nix
stackpanel.infra = {
  enable = true;
  storage-backend = {
    type = "sops";
    sops.group = "dev";  # writes to vars/dev.sops.yaml
  };
  database.enable = true;
};
```

After `infra:deploy`, the `databaseUrl` output is written to `vars/dev.sops.yaml` using `sops set` (non-destructive).

## Troubleshooting

### "Failed to decrypt secret"

**Cause:** Your AGE key is not in the group's recipient list

**Solution:**
1. Run `secrets:join` to register your key
2. Commit and push your `.age.pub` file
3. Wait for the rekey workflow (or ask a teammate to run `rekey.sh`)

### "Group not found"

**Cause:** The group hasn't been initialized

**Solution:**
```bash
secrets:init-group <group-name>
```

### "Cannot write to group file"

**Cause:** No recipients configured for the group

**Solution:**
1. Ensure the group's public key is in `config.nix`
2. Re-enter the devshell
3. Try writing the secret again

## Advanced: Creating Custom Groups

### 1. Define the Group in Nix

```nix
# .stackpanel/config.nix
stackpanel.secrets.groups = {
  analytics = {};  # Will be initialized later
  payments = {};
};
```

### 2. Initialize the Group

```bash
secrets:init-group analytics
secrets:init-group payments
```

### 3. Add Public Keys to Config

Copy the public keys printed by init-group into `config.nix`:

```nix
stackpanel.secrets.groups = {
  analytics.age-pub = "age1...";
  payments.age-pub = "age1...";
};
```

### 4. Use in UI

The new groups will appear in the group selector when creating/editing secrets.

## Summary

- **Creating**: Use the UI or `secrets:set`, select a group, enter value
- **Editing**: Click edit in UI, or `secrets:set` to overwrite
- **Groups**: Control who can decrypt (dev = everyone, prod = restricted)
- **Variable IDs**: `/<group>/<key>` encodes the group and key name
- **At runtime**: `secrets:load <group>` decrypts via SOPS directly
- **No vals references**: Secret values live in SOPS files, not as `ref+sops://` pointers
