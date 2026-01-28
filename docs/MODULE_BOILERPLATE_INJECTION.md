# Module Boilerplate Injection System

## Overview

When users install a stackpanel module (via CLI or web UI), the module's configuration boilerplate is automatically injected into their config files. This provides a smooth onboarding experience with commented examples ready to customize.

## Architecture

### 1. Automatic Detection on Shell Entry

Modules can be installed via:
- **Flake inputs**: `inputs.stackpanel-oxlint.url = "github:...";`
- **Built-in modules**: Already in `nix/stackpanel/modules/`
- **Local modules**: In `.stackpanel/modules/`

The injection system automatically detects changes and updates config files on every shell entry.

### 2. Module Metadata (`meta.nix`)

Each module defines a `configBoilerplate` field in its `meta.nix`:

```nix
{
  id = "oxlint";
  name = "OxLint";
  description = "Blazing fast JavaScript/TypeScript linter";
  
  # Boilerplate to inject into user's config
  configBoilerplate = ''
    # OxLint - Blazing fast JavaScript/TypeScript linter
    # See: https://oxc.rs
    # oxlint = {
    #   enable = true;
    #   # Global linting is handled per-app in apps.nix via app.linting.oxlint
    # };
  '';
}
```

### 3. Nix-Generated Manifest

During Nix evaluation, stackpanel generates a modules manifest at `.stackpanel/gen/modules-manifest.json`:

```json
{
  "version": 1,
  "modules": [
    {
      "id": "oxlint",
      "name": "OxLint",
      "enabled": true,
      "configBoilerplate": "# OxLint - Blazing fast...\n# oxlint = {...};"
    },
    {
      "id": "postgres",
      "name": "PostgreSQL",
      "enabled": false,
      "configBoilerplate": "# PostgreSQL - Database\n# postgres = {...};"
    }
  ]
}
```

This manifest is generated from:
- All available modules (built-in + flake inputs + local)
- Their current enabled/disabled state from `stackpanel.modules.*`
- Their boilerplate text from `meta.nix`

### 4. Injection Markers

Configuration files use special marker comments to define injection zones:

**In `.stackpanel/config.nix`:**
```nix
{
  # ... user config ...

  # 5. Injection Algorithm (Automatic on Shell Entry)

On every shell entry, `stackpanel init` runs:

1. **Read** the generated manifest at `.stackpanel/gen/modules-manifest.json`
2. **Compare** with previous injection state (stored in `.stackpanel/state/modules-injected.json`)
3. **If changed**:
   - Parse config files to find injection markers
   - Rebuild injection zones with current modules (alphabetically sorted)
   - Write back to files atomically
   - Update injection state
4. **If unchanged**: Skip injection (fast path)

**Nix side** (in shell hook or file generation):
```nix
# Generate modules manifest
stackpanel.files.entries."gen/modules-manifest.json" = {
  type = "text";
  text = builtins.toJSON {
    version = 1;
    modules = lib.mapAttrsToList (id: mod: {
      inherit id;
      name = mod.name or id;
      enabled = mod.enable or false;
      configBoilerplate = mod.meta.configBoilerplate or "";
    }) stackpanel.modulesComputed;
  };
};
```

**Go implementation sketch:**
```go
type ModulesManifest struct {
    Version int              `json:"version"`
    Modules []ModuleMetadata `json:"modules"`
}

type ModuleMetadata struct {
    ID                string `json:"id"`
    Name              string `json:"name"`
    Enabled           bool   `json:"enabled"`
    ConfigBoilerplate string `json:"configBoilerplate"`
}

func SyncModuleBoilerplates(manifestPath, configPath, statePath string) error {
    // 1. Read current manifest
    manifest, err := readManifest(manifestPath)
    if err != nil {
        return err
    }
    
    // 2. Read previous state
    prevState, _ := readState(statePath) // ignore error if first run
    
    // 3. Check if changed
    if manifestsEqual(manifest, prevState) {
        return nil // Fast path: no changes
    }
    
    // 4. Get enabled modules only
    enabled := filterEnabled(manifest.Modules)
    
    // 5. Inject into config files
    if err := injectToFile(configPath, enabled); err != nil {
        return err
    }
    
    // 6. Save new state
    return saveState(statePath, manifest)
}

func injectToFile(path string, modules []ModuleMetadata) error {
    content, _ := os.ReadFile(path)
    before, _, after := parseInjectionZone(string(content))
    
    // Build injection content
    6. User Workflow

**Installing a module via flake input:**
```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    stackpanel.url = "github:darkmatter/stackpanel";
    stackpanel-oxlint.url = "github:stackpanel-modules/oxlint";  # ← Add module
  };
  
  outputs = { stackpanel, stackpanel-oxlint, ... }: {
    # Module is automatically available
  };
}
```

**Or enabling a built-in module:**
```nix
# .stackpanel/config.nix or .stackpanel/data/modules.nix
{
  oxlint.enable = true;  # ← Enable built-in module
}
```

**On next shell entry** (`nix develop --impure`):
1. Nix re-evaluates and detects new module
2. Generates updated manifest with oxlint
3. Shell hook runs `stackpanel init`
4. CLI detects manifest change
5. Injects boilerplate automatically }
    
    injected.WriteString("  # ---------------------------------------------------------------------------\n")
    injected.WriteString("  # STACKPANEL_MODULES_END\n")
    injected.WriteString("  # ---------------------------------------------------------------------------")
    
    newContent := before + injected.String() + after
    return os.WriteFile(p
    ID          string
    Boilerplate string
}

func InjectModuleConfig(configPath string, module ModuleBoilerplate) error {
    // 1. Read file
    content, err := os.ReadFile(configPath)
    if err != nil {
        return err
    }
    
    // 2. Parse sections
    before, injected, after := parseInjectionZone(string(content))
    
    // 3. Parse existing modules in injection zone
    modules := parseModules(injected)
    
    // 4. Add/update module
    modules[module.ID] = module.Boilerplate
    
    // 5. Sort by ID
    sorted := sortModules(modules)
    
    // 6. Rebuild injection zone
    newInjected := buildInjectionZone(sorted)
    
    // 7. Write back
    newContent := before + newInjected + after
    return os.WriteFile(configPath, []byte(newContent), 0644)
}
```

### 4. Removal

When a module is uninstalled:

1. Find the module's config in the injection zone
2. Remove it
3. Rebuild the injection zone
4. Write back

User edits **outside** the injection zone are preserved.

### 5. User Workflow

**Installing a module:**
```bash
stackpanel module install oxlint
# or via web UI
```

**Result in `.stackpanel/data/modules.nix`:**
```nix
{
  # ... manual configs ...

  # ---------------------------------------------------------------------------
  # STACKPANEL_MODULES_BEGIN
  # Auto-generated module configurations (do not edit this section manually)
  # Modules are sorted alphabetically and injected by the stackpanel CLI
  # ---------------------------------------------------------------------------

  # OxLint - Blazing fast JavaScript/TypeScript linter
  # See: https://oxc.rs
  # oxlint = {
  #   enable = true;
  #   # Global linting is handled per-app in apps.nix via app.linting.oxlint
  # };

  # ---------------------------------------------------------------------------
  # STACKPANEL_MODULES_END
  # ---------------------------------------------------------------------------
}
```

**User customization:**
Users uncomment and edit the config:
```nix
  # OxLint - Blazing fast JavaScript/TypeScript linter
  # See: https://oxc.rs
  oxlint = {
    enable = true;
    # Custom settings...
  };
```

**Important:** The injection system only modifies the section between markers. User edits are preserved across re-installations.

## Injection Targets

Modules can define boilerplate for multiple targets:

```nix
# In meta.nix
{
  # Main config.nix injection
  configBoilerplate = ''...'';
  
  # Optional: data/modules.nix injection (if different)
  dataBoilerplate = ''...'';
  
  # Optional: per-app config injection
  appBoilerplate = ''...'';
}
```

## Alphabetical Sorting

Module configs are always sorted alphabetically within the injection zone. This ensures:
- Consistent ordering across all users
- Predictable diffs in version control
- Easy visual scanning

Sort order:
```nix
# STACKPANEL_MODULES_BEGIN
# biome
# oxlint
# postgres
# turbo
# STACKPANEL_MODULES_END
```

## Best Practices

### For Module Creators

1. **Keep boilerplate commented**: Users should uncomment to enable
2. **Include documentation links**: Help users learn more
3. **Provide sensible defaults**: Make the config work with minimal edits
4. **Use clear comments**: Explain what each option does
5. **Follow Nix conventions**: Proper indentation, naming
Add modules manifest generation to Nix (stackpanel.files.entries)
- [ ] Implement Go parser for injection zones
- [ ] Implement Go manifest reader and differ
- [ ] Implement Go injector (sync on shell entry)
- [ ] Add to `stackpanel init` command
- [ ] Add state tracking (.stackpanel/state/modules-injected.json)
- [ ] Test with real modules
- [ ] Add validation (ensure configs parse correctly)
- [ ] Add conflict detection (duplicate IDs)
- [Shell Hook Integration

The injection runs as part of the shell entry process:

```nix
# nix/stackpanel/devshell/hooks.nix
stackpanel.devshell.hooks.main = ''
  # ... existing hooks ...
  
  # Sync module boilerplates if manifest changed
  if [[ -f .stackpanel/gen/modules-manifest.json ]]; then
    stackpanel init --sync-modules
  fi
'';
```

Or alternatively, the manifest generation itself triggers the sync:

```nix
# Generate manifest and trigger sync in one step
stackpanel.files.entries."gen/modules-manifest.json" = {
  type = "text";
  text = builtins.toJSON manifestData;
  # Post-write hook: sync boilerplates after manifest changes
  onChange = ''
    ${pkgs.stackpanel-cli}/bin/stackpanel init --sync-modules
  '';
};
```

## Future Enhancements

1. **Multi-file injection**: Inject into multiple files from one module
2. **Template variables**: Replace `{{projectName}}` in boilerplates
3. **Conditional injection**: Only inject if certain conditions met
4. **Per-app boilerplates**: Inject into individual app config files
5. **Diff preview**: Show what will be injected on shell entry (verbose mode)
- [ ] Implement Go parser for injection zones
- [ ] Implement Go injector/remover
- [ ] Add CLI commands: `stackpanel module install/uninstall`
- [ ] Add web UI for module installation
- [ ] Add module registry API
- [ ] Test with real modules
- [ ] Add validation (ensure configs parse correctly)
- [ ] Add conflict detection (duplicate IDs)

## Future Enhancements

1. **Multi-file injection**: Inject into multiple files from one module
2. **Template variables**: Replace `{{projectName}}` in boilerplates
3. **Conditional injection**: Only inject if certain conditions met
4. **Interactive setup**: CLI wizard for module configuration
5. **Diff preview**: Show what will be injected before installation
