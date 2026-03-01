# Documentation Update Summary

## Overview

Updated all Stackpanel documentation to reflect the current app-centric deployment configuration structure. The old provider-centric structure (`stackpanel.deployment.fly.apps.*`) has been replaced with per-app configuration (`stackpanel.apps.<name>.deployment.*`).

## Files Updated

### 1. Deployment Documentation

#### `apps/docs/content/docs/deployment/fly.mdx`
- **Changed:** Removed references to global `stackpanel.deployment.fly.enable`
- **Changed:** Updated all examples to use `stackpanel.apps.<name>.deployment.host = "fly"`
- **Changed:** Updated field names from kebab-case to camelCase (e.g., `app-name` → `appName`)
- **Changed:** Removed outdated OIDC config structure
- **Changed:** Updated database configuration section to use Fly CLI instead of declarative config
- **Changed:** Fixed container build commands to use correct output path
- **Changed:** Updated multi-region deployment guidance
- **Removed:** References to `stackpanel.deployment.fly.apps.*`

#### `apps/docs/content/docs/deployment/cloudflare.mdx`
- **Changed:** Removed global `stackpanel.deployment.cloudflare.enable` requirement
- **Changed:** Updated all examples to use `stackpanel.apps.<name>.deployment.host = "cloudflare"`
- **Changed:** Moved from `deployment.cloudflare.workers.*` to `apps.<name>.deployment.cloudflare.*`
- **Changed:** Updated field names to camelCase
- **Changed:** Consolidated bindings configuration (KV, R2, D1) into per-app deployment section
- **Changed:** Updated CI integration section with current config structure
- **Removed:** References to separate `.workers` and `.pages` sections

#### `apps/docs/content/docs/deployment/index.mdx`
- **Changed:** Updated deployment flow diagram to show current app-based structure
- **Changed:** Fixed examples from `stackpanel.deployment.fly.apps.api` to `stackpanel.apps.api.deployment`
- **Changed:** Updated container reference from `stackpanel.containers.api` to `stackpanel.apps.api.container`

#### `apps/docs/content/docs/deployment/containers.mdx`
- **Changed:** Fixed all container build commands from `.#containers.<name>` to `.#packages.x86_64-linux.container-<name>`
- **Changed:** Added `--impure` flag to all nix build commands
- **Changed:** Updated registry push examples to use Docker/skopeo instead of non-existent `.copyToRegistry`
- **Changed:** Fixed `nix path-info` command to use correct output path

### 2. Top-Level Documentation

#### `docs/deploy.md`
- **Replaced:** Completely rewrote from minimal stub to comprehensive deployment guide
- **Added:** Container building instructions with correct commands
- **Added:** Configuration examples for both inline and separate container definitions
- **Added:** Deployment target configuration examples
- **Added:** Links to full documentation

### 3. Migration Guide

#### `docs/DEPLOYMENT_MIGRATION.md` (NEW)
- **Created:** Comprehensive migration guide for users with old config
- **Added:** Side-by-side comparison of old vs. new structure
- **Added:** Step-by-step migration instructions for Fly.io and Cloudflare
- **Added:** Field name mapping table
- **Added:** Common error messages with solutions
- **Added:** Benefits explanation of new structure

## Key Changes Summary

### Configuration Structure

**OLD (No longer supported):**
```nix
stackpanel.deployment.fly.apps.web = {
  region = "iad";
  vm-size = "shared-cpu-1x";
};
```

**NEW (Current):**
```nix
stackpanel.apps.web = {
  deployment = {
    enable = true;
    host = "fly";
    fly = {
      appName = "myapp-web";
      region = "iad";
      memory = "512mb";
    };
  };
};
```

### Container Build Commands

**OLD:**
```bash
nix build .#containers.api
```

**NEW:**
```bash
nix build --impure .#packages.x86_64-linux.container-api
```

### Field Name Changes

| Old Name | New Name |
|----------|----------|
| `app-name` | `appName` |
| `account-id` | `accountId` |
| `vm-size` | `memory` + `cpus` |
| `compatibility-date` | `compatibilityDate` |
| `kv-namespaces` | `kvNamespaces` |
| `r2-buckets` | `r2Buckets` |
| `d1-databases` | `d1Databases` |

## Breaking Changes

1. **Removed:** `stackpanel.deployment.fly.apps.*` - Use `stackpanel.apps.<name>.deployment.fly` instead
2. **Removed:** `stackpanel.deployment.cloudflare.workers.*` - Use `stackpanel.apps.<name>.deployment.cloudflare` instead
3. **Removed:** `stackpanel.deployment.cloudflare.pages.*` - Use `stackpanel.apps.<name>.deployment.cloudflare` with type
4. **Changed:** Container output from `.#containers.<name>` to `.#packages.<system>.container-<name>`
5. **Changed:** All deployment field names from kebab-case to camelCase

## Error Resolution

### "The option `stackpanel.deployment.fly.apps' does not exist"

This error indicates old configuration structure. Solution:

1. Remove all `stackpanel.deployment.fly.apps.*` config
2. Remove all `stackpanel.deployment.cloudflare.workers.*` and `.pages.*` config
3. Move deployment config into each app's `deployment` section
4. Set `host` to target provider
5. Add provider-specific config under provider name

See `docs/DEPLOYMENT_MIGRATION.md` for detailed migration steps.

## Documentation Quality Improvements

1. **Consistency:** All examples now use current API
2. **Clarity:** Removed confusing global "enable" flags
3. **Accuracy:** Fixed all container build commands
4. **Completeness:** Added migration guide for users with old config
5. **Discoverability:** Updated deployment index with correct structure

## Testing Recommendations

1. Test `nix develop` with fresh config to verify no errors
2. Build containers with updated commands
3. Verify deployment config validation works
4. Check that CI generation produces correct output
5. Ensure devshell includes correct CLIs (flyctl, wrangler) based on app config

## Next Steps

1. Consider deprecation warnings for old config structure (if not already present)
2. Add validation to detect old structure and suggest migration
3. Update any video tutorials or external documentation
4. Consider adding `stackpanel migrate-deployment` command to automate migration
5. Update changelog with migration guide reference

## Files That Don't Need Changes

- Code implementation in `nix/stackpanel/deployment/` - already uses new structure
- Proto schemas - already define current structure
- Core options in `nix/stackpanel/core/options/apps.nix` - already correct
- README.md - doesn't mention deployment specifics

## Verification

All documentation now:
- ✅ Uses `stackpanel.apps.<name>.deployment.*` structure
- ✅ Shows correct container build commands with system prefix
- ✅ Uses camelCase for field names
- ✅ References correct output paths
- ✅ Includes `--impure` flag where needed
- ✅ Has no references to deprecated config structure