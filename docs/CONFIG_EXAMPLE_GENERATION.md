# Config Example Generation with Option Descriptions

## Overview

Stackpanel can now generate an annotated `config.nix.example` file with inline documentation extracted from option descriptions. This makes it easier for users to understand available configuration options without reading separate documentation.

## Features

- **Auto-generated documentation**: Extracts descriptions from Nix module options
- **Inline comments**: Adds helpful comments explaining each configuration option
- **Flexible output**: Toggle comments on/off for minimal or comprehensive examples
- **Current config reference**: Optionally uses your current config as a structure reference
- **Always up-to-date**: Regenerates from live option definitions

## Usage

### Basic Usage

Generate an annotated config example in your devshell:

```bash
generate-config-example
```

This creates `.stackpanel/config.nix.example` with inline documentation.

### Without Comments

For a minimal example without documentation comments:

```bash
generate-config-example --no-comments
```

### Custom Output Location

Specify a custom output path:

```bash
generate-config-example --output /path/to/example.nix
generate-config-example -o ~/Desktop/config-example.nix
```

### Help

```bash
generate-config-example --help
```

## Example Output

### With Comments (Default)

```nix
# ==============================================================================
# config.nix.example
#
# Stackpanel project configuration example with inline documentation.
#
# This file is auto-generated from option descriptions. Copy sections you need
# to your config.nix and customize as needed.
#
# To regenerate: run 'generate-config-example' in your devshell
# For minimal version: run 'generate-config-example --no-comments'
# ==============================================================================
{
  # ---------------------------------------------------------------------------
  # Enable
  # ---------------------------------------------------------------------------
  # Whether to enable Stackpanel for this project. When false, all Stackpanel
  # features are disabled and the devshell becomes a minimal Nix shell.
  enable = true;

  # ---------------------------------------------------------------------------
  # Name
  # ---------------------------------------------------------------------------
  # Project name. Used for service ports, Caddy domains, and generated files.
  # Must be a valid identifier (alphanumeric, dashes, underscores).
  name = "my-project";

  # ---------------------------------------------------------------------------
  # Apps
  # ---------------------------------------------------------------------------
  # Application definitions. Each app gets a deterministic port and optional
  # Caddy virtual host. Apps can specify deployment targets, containers,
  # build commands, and framework-specific configuration.
  apps = {
    web = {
      # Port offset from base port (null = auto-assign by position)
      port = 0;

      # Application root directory (relative to project root)
      path = "./apps/web";

      # Human-readable description
      description = "Web application";

      # Framework configuration
      framework = {
        tanstack-start = {
          # Enable TanStack Start framework support
          enable = true;
        };
      };

      # Deployment configuration
      deployment = {
        # Enable deployment for this app
        enable = false;

        # Deployment host/platform (cloudflare, fly, vercel, aws)
        host = "cloudflare";

        # Cloudflare-specific deployment settings
        cloudflare = {
          # Worker name
          workerName = "my-app";

          # Deployment type (vite/worker/pages)
          type = "CLOUDFLARE_WORKER_TYPE_VITE";
        };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Deployment
  # ---------------------------------------------------------------------------
  # Global deployment configuration shared across all apps
  deployment = {
    # Default deployment host for apps that don't specify one
    defaultHost = "cloudflare";

    # Fly.io global settings
    fly = {
      # Fly.io organization slug
      organization = "";

      # Default region for new deployments
      defaultRegion = "iad";
    };

    # Cloudflare global settings
    cloudflare = {
      # Cloudflare account ID (from dashboard)
      accountId = "";

      # Workers API compatibility date
      compatibilityDate = "2024-01-01";
    };
  };

  # ... more sections ...
}
```

### Without Comments (--no-comments)

```nix
# ==============================================================================
# config.nix.example
#
# Stackpanel project configuration example with inline documentation.
#
# Minimal configuration example without inline documentation.
# Run 'generate-config-example' (without --no-comments) for annotated version.
# ==============================================================================
{
  enable = true;
  name = "my-project";

  apps = {
    web = {
      port = 0;
      path = "./apps/web";
      description = "Web application";
    };
  };

  deployment = {
    defaultHost = "cloudflare";
  };
}
```

## How It Works

### Architecture

1. **Option Extraction**: Uses `pkgs.nixosOptionsDoc` to extract option metadata from Nix modules
2. **JSON Export**: Converts options to JSON including descriptions, types, defaults, and examples
3. **Go Generator**: Processes the JSON and generates formatted Nix configuration with comments
4. **Output**: Writes annotated `config.nix.example` file

### Data Flow

```
Nix Module Options
    ↓
nixosOptionsDoc (builds options.json)
    ↓
Go CLI (config generate-example)
    ↓
config.nix.example (with inline docs)
```

### File Locations

- **Module**: `.stackpanel/modules/generate-config-example.nix`
- **Go Implementation**: `apps/stackpanel-go/cmd/cli/config_generate_example.go`
- **Generated Output**: `.stackpanel/config.nix.example` (default)

## Implementation Details

### Nix Module

The generation module (`.stackpanel/modules/generate-config-example.nix`) provides:

- Shell script wrapper that builds options JSON
- Integration with existing Go CLI
- Argument parsing for flags
- Error handling and user feedback

### Go CLI Command

The Go implementation (`config_generate_example.go`) provides:

```go
type OptionInfo struct {
    Description  string          // Human-readable description
    Type         json.RawMessage // Option type (string, bool, attrs, etc.)
    Default      json.RawMessage // Default value if any
    Example      json.RawMessage // Example value if provided
    Declarations []string        // Source file locations
    ReadOnly     bool            // Whether option is read-only
    Internal     bool            // Whether option is internal
}
```

Features:
- Filters out internal and read-only options
- Groups options by top-level keys
- Wraps long descriptions to fit comment width
- Generates appropriate placeholder values based on type
- Preserves hierarchical structure

### Option Priority

When generating example values, the following priority is used:

1. **Example** - If option has an explicit example value
2. **Default** - If option has a default value
3. **Type-based placeholder** - Inferred from option type:
   - `bool` → `false`
   - `int` → `0`
   - `string` → `""`
   - `list` → `[ ]`
   - `attrs` → `{ }`
   - `path` → `"./path"`
   - `package` → `pkgs.package-name`

## Benefits

### For Users

- **Self-documenting**: Configuration files include documentation inline
- **Discoverable**: Easy to find available options without external docs
- **Copy-paste friendly**: Grab the sections you need and customize
- **Always current**: Regenerates from actual option definitions

### For Development

- **Single source of truth**: Option descriptions in Nix are the documentation
- **Auto-updates**: Documentation stays in sync with code automatically
- **Reduced maintenance**: No separate config examples to keep updated
- **Better DX**: Users get immediate feedback about what options do

## Adding Documentation to Options

When defining new options in Nix modules, add descriptions:

```nix
options.stackpanel.myFeature = {
  enable = lib.mkEnableOption "my feature";

  setting = lib.mkOption {
    type = lib.types.str;
    default = "default-value";
    description = ''
      This setting controls the behavior of my feature.
      
      It accepts string values and defaults to "default-value".
      Use this when you need to configure xyz.
    '';
    example = "custom-value";
  };

  nested = {
    option = lib.mkOption {
      type = lib.types.int;
      default = 42;
      description = "A nested configuration option for fine-tuning behavior";
    };
  };
};
```

The `description` field will automatically appear as inline comments in the generated config example.

## Best Practices

### Writing Option Descriptions

1. **Be concise**: First sentence should be a clear summary
2. **Explain purpose**: What does this option control?
3. **Give context**: When would you use this?
4. **Include constraints**: Valid values, formats, requirements
5. **Reference related options**: Link to related configuration

Example:

```nix
description = ''
  Deployment host/platform. Combined with `framework` to determine
  the alchemy resource type:

    framework × host → alchemy resource
    tanstack-start × cloudflare → TanStackStart
    nextjs × cloudflare → Nextjs
    * × fly → Fly container
'';
```

### Regenerating Documentation

Regenerate after:
- Adding new options to modules
- Updating option descriptions
- Changing option types or defaults
- Major refactoring of configuration structure

```bash
# In your devshell
generate-config-example
```

## Integration with Documentation

This feature complements (not replaces) other documentation:

- **config.nix.example**: Quick reference, copy-paste ready
- **Fumadocs MDX**: Comprehensive guides, tutorials, examples
- **Options reference**: Full API documentation with search

Run `generate-docs` to also regenerate the MDX documentation.

## Troubleshooting

### "Failed to generate options JSON"

The Nix evaluation failed. Check:
- Your `.stackpanel/config.nix` is valid
- No syntax errors in imported modules
- Options are properly defined

### Output is empty or minimal

Check:
- Options have `description` fields
- Options are not marked `internal = true` or `readOnly = true`
- Module is imported in `.stackpanel/modules/default.nix`

### Comments are too verbose

Use the `--no-comments` flag for a minimal version without documentation.

## Future Enhancements

Potential improvements:

- [ ] Interactive mode to select which sections to include
- [ ] Diff view against current config.nix
- [ ] Format validation of generated output
- [ ] Support for option "since" versions
- [ ] Link to online documentation for each option
- [ ] Generate separate examples per feature area

## Related Documentation

- [Options Documentation](../apps/docs/content/docs/reference) - Full API reference
- [Configuration Guide](../README.md) - Getting started with config.nix
- [Module System](./MODULE_BOILERPLATE_INJECTION.md) - How modules work
- [Deployment Config Migration](./DEPLOYMENT_MIGRATION.md) - Migrating deployment config

## Changelog

### Initial Implementation

- Added `generate-config-example` command
- Extracts option descriptions from Nix modules
- Generates annotated config.nix.example
- Supports `--no-comments` flag for minimal output
- Integrated with existing Go CLI