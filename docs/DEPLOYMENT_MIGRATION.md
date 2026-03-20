# Deployment Configuration Migration Guide

## Summary of Changes

Stack's deployment configuration has been refactored from a provider-centric structure to an **app-centric structure**. This makes it clearer which apps deploy where and reduces configuration duplication.

## Breaking Changes

### Old Structure (Deprecated)

```nix
# ❌ OLD - No longer supported
stack.deployment.fly.apps.web = {
  region = "iad";
  vm-size = "shared-cpu-1x";
};

stack.deployment.cloudflare.workers.api = {
  app = "api";
  name = "myapp-api";
};
```

### New Structure (Current)

```nix
# ✅ NEW - Current API
stack.apps.web = {
  port = 0;
  root = "./apps/web";
  
  deployment = {
    enable = true;
    host = "fly";
    
    fly = {
      appName = "myapp-web";
      region = "iad";
      memory = "512mb";
      cpus = 1;
    };
  };
};

stack.apps.api = {
  port = 1;
  root = "./apps/api";
  
  deployment = {
    enable = true;
    host = "cloudflare";
    
    cloudflare = {
      workerName = "myapp-api";
      type = "CLOUDFLARE_WORKER_TYPE_WORKER";
    };
  };
};
```

## Migration Steps

### 1. Move Fly.io Configuration

**Before:**
```nix
stack.deployment.fly = {
  enable = true;
  organization = "my-org";
  
  apps.api = {
    app-name = "myapp-api";
    region = "iad";
    vm = {
      size = "shared-cpu-1x";
      memory = 256;
    };
  };
};
```

**After:**
```nix
# Global Fly settings (optional)
stack.deployment = {
  fly = {
    organization = "my-org";
    defaultRegion = "iad";
  };
};

# Per-app configuration
stack.apps.api = {
  port = 1;
  root = "./apps/api";
  
  deployment = {
    enable = true;
    host = "fly";
    
    fly = {
      appName = "myapp-api";
      region = "iad";
      memory = "256mb";
      cpus = 1;
    };
  };
};
```

### 2. Move Cloudflare Configuration

**Before:**
```nix
stack.deployment.cloudflare = {
  enable = true;
  account-id = "abc123";
  
  workers.api = {
    app = "api";
    name = "myapp-api";
    vars = {
      APP_ENV = "production";
    };
  };
  
  pages.docs = {
    app = "docs";
    project-name = "myapp-docs";
  };
};
```

**After:**
```nix
# Global Cloudflare settings (optional)
stack.deployment = {
  cloudflare = {
    accountId = "abc123";
    compatibilityDate = "2024-01-01";
  };
};

# Per-app configuration
stack.apps.api = {
  port = 1;
  root = "./apps/api";
  
  deployment = {
    enable = true;
    host = "cloudflare";
    
    cloudflare = {
      workerName = "myapp-api";
      type = "CLOUDFLARE_WORKER_TYPE_WORKER";
      bindings = {
        APP_ENV = "production";
      };
    };
  };
};

stack.apps.docs = {
  port = 2;
  root = "./apps/docs";
  
  deployment = {
    enable = true;
    host = "cloudflare";
    
    cloudflare = {
      workerName = "myapp-docs";
      type = "CLOUDFLARE_WORKER_TYPE_PAGES";
    };
  };
};
```

### 3. Update Container Build Commands

**Before:**
```bash
nix build .#containers.api
```

**After:**
```bash
nix build --impure .#packages.x86_64-linux.container-api

# Or use the convenience script
container-build api
```

### 4. Field Name Changes

Several field names have changed to use camelCase instead of kebab-case:

| Old Name | New Name |
|----------|----------|
| `app-name` | `appName` |
| `account-id` | `accountId` |
| `vm-size` | Use `memory` and `cpus` separately |
| `compatibility-date` | `compatibilityDate` |
| `project-name` | `workerName` |
| `kv-namespaces` | `kvNamespaces` |
| `r2-buckets` | `r2Buckets` |
| `d1-databases` | `d1Databases` |

## Removing Old Configuration

1. **Remove global deployment enables:**
   - Delete `stack.deployment.fly.enable = true;`
   - Delete `stack.deployment.cloudflare.enable = true;`

2. **Remove provider-specific app sections:**
   - Delete `stack.deployment.fly.apps.*`
   - Delete `stack.deployment.cloudflare.workers.*`
   - Delete `stack.deployment.cloudflare.pages.*`

3. **Move configuration into app definitions:**
   - Add `deployment` section to each app in `stack.apps.*`
   - Set `host` to the desired provider
   - Add provider-specific config under the provider name

## Common Issues

### Error: "The option `stack.deployment.fly.apps' does not exist"

This error means you're using the old configuration structure. Follow the migration steps above to move your configuration to the new app-centric structure.

**Quick fix:**
```nix
# Find this in your config:
stack.deployment.fly.apps.myapp = { ... };

# Replace with:
stack.apps.myapp = {
  # ... existing app config ...
  deployment = {
    enable = true;
    host = "fly";
    fly = { ... };  # Move fly.apps.myapp config here
  };
};
```

### Error: "No such attribute 'containers'"

Container outputs have moved from `.#containers.<name>` to `.#packages.<system>.container-<name>`.

**Quick fix:**
```bash
# Old:
nix build .#containers.api

# New:
nix build --impure .#packages.x86_64-linux.container-api
```

### Deployment Not Working After Migration

1. **Check that `deployment.enable = true`** for each app you want to deploy
2. **Verify `deployment.host` is set** to your target platform
3. **Ensure global deployment settings** (like `accountId`, `organization`) are set if needed
4. **Rebuild your devshell** with `nix develop --impure` or `direnv reload`

## Benefits of the New Structure

1. **Clearer ownership:** Each app declares its own deployment configuration
2. **Less duplication:** No need to reference app names in two places
3. **Better IDE support:** Configuration is co-located with app definitions
4. **Easier multi-platform:** Mix Fly.io, Cloudflare, and other providers in one place
5. **Type safety:** Per-app options are now properly typed and validated

## Need Help?

- Check the [deployment documentation](https://stack.dev/docs/deployment)
- Review the [Fly.io guide](https://stack.dev/docs/deployment/fly)
- Review the [Cloudflare guide](https://stack.dev/docs/deployment/cloudflare)
- Open an issue if you find migration problems