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
1. The value is written to `.stackpanel/secrets/vars/<group>.sops.yaml` (SOPS-encrypted)
2. A variable entry is created with a vals reference
3. The reference is: `ref+sops://.stackpanel/secrets/vars/<group>.sops.yaml#/<key>`

## Editing an Existing Secret

1. Find the secret in the Variables panel
2. Click **"Edit"** 
3. You'll see the **group selector** - you can change which group it belongs to
4. Update the value
5. Click **"Save Changes"**

The secret will be re-encrypted to the new group's recipients if you changed groups.

## Understanding Groups

### What is a Group?

A group is an **access control boundary**. Each group has:
- Its own SOPS-encrypted YAML file
- Specific AGE recipients (who can decrypt)
- A separate encryption key

### Default Groups

- **dev** - For development secrets, typically accessible by all team members
- **staging** - For staging environment, may have restricted access
- **prod** - For production secrets, highly restricted access

### Group Access Control

Access to each group is controlled by the `.sops.yaml` configuration:

```yaml
# .stackpanel/secrets/vars/.sops.yaml
creation_rules:
  # Dev: Everyone
  - path_regex: ^dev\.sops\.yaml$
    key_groups:
      - age:
          - alice_key
          - bob_key
          - ci_key
  
  # Prod: Restricted
  - path_regex: ^prod\.sops\.yaml$
    key_groups:
      - age:
          - alice_key  # Only admin
          - ci_key     # Only CI
```

## Using Secrets in Apps

### In App Environments

When you create a secret, it automatically generates a vals reference. Use this in your app configs:

```nix
# apps.nix
{
  apps.web.environments.dev.env = {
    DATABASE_URL = "ref+sops://.stackpanel/secrets/vars/dev.sops.yaml#/DATABASE_URL";
  };
  
  apps.web.environments.prod.env = {
    DATABASE_URL = "ref+sops://.stackpanel/secrets/vars/prod.sops.yaml#/DATABASE_URL";
  };
}
```

### At Runtime

The `vals` tool automatically resolves these references:

```bash
# Decrypt all secrets for an app/env
vals eval -f packages/env/data/apps/web/dev.yaml

# Load into environment
eval $(vals env packages/env/data/apps/web/dev.yaml)
```

## Best Practices

### 1. Choose the Right Group

- **dev** - Non-production data, test API keys, local database URLs
- **staging** - Pre-production data that mirrors prod structure
- **prod** - Production credentials, live API keys, customer data

### 2. Minimize Prod Access

Only add AGE keys to the prod group for:
- Ops team leads
- CI/CD systems
- On-call engineers (if needed)

### 3. Group by Sensitivity, Not Environment

While the defaults are dev/staging/prod, you can create groups like:
- `analytics` - Analytics service credentials
- `payments` - Payment processor keys
- `internal-tools` - Admin panel credentials

### 4. Use Descriptive Names

Instead of:
```
/my-secret
```

Use:
```
/stripe-api-key-production
/postgres-url-analytics
```

## Common Workflows

### Sharing a Secret Across Environments

**Option 1: Same group, different apps**
```nix
apps.web.environments.dev.env.SHARED_API_KEY = 
  "ref+sops://.stackpanel/secrets/vars/dev.sops.yaml#/EXTERNAL_API_KEY";

apps.api.environments.dev.env.SHARED_API_KEY = 
  "ref+sops://.stackpanel/secrets/vars/dev.sops.yaml#/EXTERNAL_API_KEY";
```

**Option 2: Different groups per environment**
```nix
apps.web.environments.dev.env.API_KEY = 
  "ref+sops://.stackpanel/secrets/vars/dev.sops.yaml#/API_KEY";

apps.web.environments.prod.env.API_KEY = 
  "ref+sops://.stackpanel/secrets/vars/prod.sops.yaml#/API_KEY";
```

### Promoting Secrets from Dev to Prod

1. In the UI, create the secret in the **dev** group
2. Test it works in development
3. Create a **new secret** in the **prod** group with the production value
4. Update your prod environment config to reference the prod group

**Don't** move the same secret value from dev to prod - use different credentials per environment!

### Rotating a Secret

1. Generate the new credential value
2. Edit the secret in the UI (same group)
3. Update the value
4. Deploy your apps to pick up the new value

## Troubleshooting

### "Failed to decrypt secret"

**Cause:** Your AGE key is not in the group's recipient list

**Solution:**
1. Check `.sops.yaml` to see which keys can decrypt the group
2. Add your AGE public key to the group's creation rule
3. Run `sops updatekeys .stackpanel/secrets/vars/<group>.sops.yaml` to re-encrypt

### "Group not found"

**Cause:** The group hasn't been initialized

**Solution:**
```bash
# Initialize the group
secrets:init-group <group-name>
```

### "Cannot write to group file"

**Cause:** No recipients configured for the group

**Solution:**
1. Ensure the group is defined in `.sops.yaml`
2. Add at least one AGE public key as a recipient
3. Try writing the secret again

## Advanced: Creating Custom Groups

### 1. Define the Group in Nix

```nix
# .stackpanel/config.nix
{
  stackpanel.secrets.groups = {
    analytics = {};  # Will be initialized later
    payments = {};
  };
}
```

### 2. Initialize the Group

```bash
secrets:init-group analytics
secrets:init-group payments
```

### 3. Configure Recipients

Edit `.sops.yaml`:

```yaml
creation_rules:
  - path_regex: ^analytics\.sops\.yaml$
    key_groups:
      - age:
          - alice_key
          - analytics_service_key
```

### 4. Use in UI

The new groups will appear in the group selector when creating/editing secrets.

## Migration from .age Files

If you have existing secrets in `.stackpanel/secrets/vars/*.age`:

1. **Create the secret in the UI** with the same key name and new group
2. **Delete the old .age file**
3. **Update references** in your configs to use the vals reference

The old .age system is deprecated but still works for backward compatibility.

## Summary

- **Creating**: Use the UI, select a group, enter value
- **Editing**: Click edit, change group or value as needed
- **Groups**: Control who can decrypt (dev = everyone, prod = restricted)
- **In code**: Vals references are generated automatically
- **At runtime**: `vals` resolves references by decrypting SOPS files

For more details, see `SECRETS_REFACTOR.md` and `packages/env/ARCHITECTURE.md`.