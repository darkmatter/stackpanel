# Deployment Configuration Fix Checklist

Use this checklist if you're getting errors like:
```
error: The option `stack.deployment.fly.apps' does not exist.
```

## Quick Fix Steps

### Step 1: Find Your Config Files

Check these locations for deployment config:
- [ ] `flake.nix` - Main configuration
- [ ] `.stack/config.nix` - Local overrides
- [ ] `.stack/config.local.nix` - Local-only settings
- [ ] Any imported config files referenced in your flake

### Step 2: Search for Old Patterns

Search your config files for these **outdated** patterns:
- [ ] `stack.deployment.fly.apps`
- [ ] `stack.deployment.cloudflare.workers`
- [ ] `stack.deployment.cloudflare.pages`
- [ ] `deployment.fly.enable = true` (at global level)
- [ ] `deployment.cloudflare.enable = true` (at global level)

### Step 3: Update Each App

For **each app** that needs deployment, update the config:

#### ❌ OLD (Remove this)
```nix
stack.deployment.fly.apps.myapp = {
  region = "iad";
  vm-size = "shared-cpu-1x";
};
```

#### ✅ NEW (Use this)
```nix
stack.apps.myapp = {
  port = 1;  # or your app's port
  root = "./apps/myapp";
  
  deployment = {
    enable = true;
    host = "fly";  # or "cloudflare", "vercel", etc.
    
    fly = {
      appName = "myapp";
      region = "iad";
      memory = "512mb";
      cpus = 1;
    };
  };
};
```

### Step 4: Update Global Settings (Optional)

Global deployment settings are now under `stack.deployment` directly:

#### ❌ OLD
```nix
stack.deployment.fly = {
  enable = true;
  organization = "my-org";
};
```

#### ✅ NEW
```nix
stack.deployment = {
  fly = {
    organization = "my-org";
    defaultRegion = "iad";
  };
};
```

### Step 5: Update Field Names

Replace kebab-case with camelCase:

- [ ] `app-name` → `appName`
- [ ] `account-id` → `accountId`
- [ ] `vm-size` → Use `memory` and `cpus` separately
- [ ] `compatibility-date` → `compatibilityDate`
- [ ] `project-name` → `workerName`
- [ ] `kv-namespaces` → `kvNamespaces`
- [ ] `r2-buckets` → `r2Buckets`
- [ ] `d1-databases` → `d1Databases`

### Step 6: Update Container Commands

If you have scripts or documentation with container builds:

#### ❌ OLD
```bash
nix build .#containers.myapp
```

#### ✅ NEW
```bash
nix build --impure .#packages.x86_64-linux.container-myapp
```

### Step 7: Rebuild and Test

```bash
# Clean and rebuild
rm -rf .devenv
nix flake lock --update-input stack  # Optional: update to latest
nix develop --impure

# Or with direnv
direnv reload
```

## Verification

After making changes, verify:

- [ ] `nix develop --impure` runs without errors
- [ ] No error about `deployment.fly.apps` or similar
- [ ] Apps show up correctly in Stack studio
- [ ] Container builds work with new path
- [ ] Deployment config appears in generated files

## Common Mistakes

1. **Forgetting `deployment.enable = true`**
   - Each app needs `deployment.enable = true` to be deployed

2. **Not setting `deployment.host`**
   - You must specify `host = "fly"` or `host = "cloudflare"` etc.

3. **Using old field names**
   - All fields are now camelCase, not kebab-case

4. **Leaving old global enables**
   - Remove `stack.deployment.fly.enable = true`
   - Remove `stack.deployment.cloudflare.enable = true`

5. **Wrong container path**
   - Use `.#packages.<system>.container-<name>` not `.#containers.<name>`

## Example: Complete Migration

### Before (OLD)
```nix
{
  stack.deployment.fly = {
    enable = true;
    organization = "acme";
    
    apps.api = {
      app-name = "acme-api";
      region = "iad";
      vm-size = "shared-cpu-1x";
    };
  };
  
  stack.deployment.cloudflare = {
    enable = true;
    account-id = "abc123";
    
    workers.web = {
      app = "web";
      name = "acme-web";
    };
  };
}
```

### After (NEW)
```nix
{
  # Global deployment settings (optional)
  stack.deployment = {
    fly.organization = "acme";
    cloudflare.accountId = "abc123";
  };
  
  # App definitions with deployment config
  stack.apps = {
    api = {
      port = 1;
      root = "./apps/api";
      
      deployment = {
        enable = true;
        host = "fly";
        fly = {
          appName = "acme-api";
          region = "iad";
          memory = "512mb";
          cpus = 1;
        };
      };
    };
    
    web = {
      port = 0;
      root = "./apps/web";
      
      deployment = {
        enable = true;
        host = "cloudflare";
        cloudflare = {
          workerName = "acme-web";
          type = "CLOUDFLARE_WORKER_TYPE_VITE";
        };
      };
    };
  };
}
```

## Still Stuck?

1. Check the full migration guide: `docs/DEPLOYMENT_MIGRATION.md`
2. Review documentation: https://stack.dev/docs/deployment
3. Look at example configs in `nix/flake/templates/`
4. Open an issue with your config (sanitized)

## Summary

The key change: **Move deployment config from provider-centric to app-centric structure.**

Instead of defining apps under deployment providers, define deployment settings within each app.