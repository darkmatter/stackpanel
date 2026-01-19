# Stackpanel Extensions

Extensions are feature modules that compose core stackpanel features to provide integrated functionality. They are the primary way to add new capabilities to a stackpanel project.

## Overview

An extension is a Nix module that:
1. Defines its own configuration options under `stackpanel.<extensionName>.*`
2. Registers itself in the extensions system for UI visibility
3. Uses core stackpanel features to implement functionality

## Core Features Available to Extensions

Extensions can use any of these core stackpanel features:

| Feature | Option Path | Description |
|---------|-------------|-------------|
| **File Generation** | `stackpanel.files.entries` | Generate files into the project workspace |
| **Scripts/Commands** | `stackpanel.scripts` | Add CLI commands to the devshell |
| **Packages** | `stackpanel.devshell.packages` | Add packages to the devshell |
| **Tasks** | `stackpanel.tasks` | Define runnable tasks |
| **Shell Hooks** | `stackpanel.devshell.hooks` | Run code on shell entry |
| **Variables/Secrets** | `stackpanel.secrets` | Manage secrets and variables |
| **Services** | `stackpanel.services` | Configure background services |
| **MOTD** | `stackpanel.motd` | Add entries to the shell greeting |

## Extension Types

### Builtin Extensions

Shipped with stackpanel. Examples: `sst`, `ci`, `docker`.

```nix
stackpanel.extensions.sst = {
  name = "SST Infrastructure";
  enabled = true;
  builtin = true;  # Mark as builtin
  # ...
};
```

### Local Extensions

Defined in the project's Nix configuration:

```nix
stackpanel.extensions.my-feature = {
  name = "My Feature";
  enabled = true;
  source.type = "EXTENSION_SOURCE_TYPE_LOCAL";
  source.path = "./nix/extensions/my-feature.nix";
};
```

### External Extensions

Installed from GitHub or other sources:

```nix
stackpanel.extensions.some-extension = {
  name = "Some Extension";
  enabled = true;
  source = {
    type = "EXTENSION_SOURCE_TYPE_GITHUB";
    repo = "someorg/stackpanel-extension";
    ref = "main";
  };
};
```

## Extension Schema

Each extension has these fields:

```nix
{
  # Identity
  name = "Display Name";                    # Required: Human-readable name
  description = "What this extension does"; # Optional: Description

  # Status
  enabled = true;                           # Whether the extension is active
  builtin = false;                          # Whether shipped with stackpanel

  # Source (for non-builtin extensions)
  source = {
    type = "EXTENSION_SOURCE_TYPE_GITHUB";  # builtin, local, github, npm, url
    repo = "org/repo";                      # GitHub repo
    ref = "main";                           # Git ref
    path = "./local/path";                  # Local path
    module-path = "nix/module.nix";         # Path within source
  };

  # Organization
  category = "EXTENSION_CATEGORY_INFRASTRUCTURE"; # For UI grouping
  priority = 100;                           # Load order (lower = earlier)
  tags = [ "aws" "infrastructure" ];        # For filtering
  dependencies = [ "other-extension" ];     # Required extensions

  # Feature flags (what core features this uses)
  features = {
    files = true;      # Uses stackpanel.files
    scripts = true;    # Uses stackpanel.scripts
    tasks = false;     # Uses stackpanel.tasks
    secrets = true;    # Uses stackpanel.secrets
    shell-hooks = false;
    packages = true;
    services = false;
    checks = false;
  };

  # UI panels for the web interface
  panels = [
    {
      id = "my-panel";
      title = "Panel Title";
      type = "PANEL_TYPE_STATUS";  # STATUS, APPS_GRID, FORM, TABLE, CUSTOM
      order = 1;
      fields = [
        { name = "metrics"; type = "FIELD_TYPE_STRING"; value = "..."; }
      ];
    }
  ];

  # Per-app data
  apps = {
    my-app = {
      enabled = true;
      config = { key = "value"; };
    };
  };
}
```

## Creating a Builtin Extension

Here's the pattern for creating a builtin extension (using SST as example):

### 1. Create the Module File

```nix
# nix/stackpanel/my-extension/default.nix
{ ... }:
{
  imports = [ ./my-extension.nix ];
}
```

```nix
# nix/stackpanel/my-extension/my-extension.nix
{ pkgs, lib, config, ... }:
let
  cfg = config.stackpanel.my-extension;
in
{
  # Define extension-specific options
  options.stackpanel.my-extension = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable my extension";
    };
    
    some-setting = lib.mkOption {
      type = lib.types.str;
      default = "default-value";
      description = "A setting for the extension";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register the extension
    stackpanel.extensions.my-extension = {
      name = "My Extension";
      enabled = true;
      builtin = true;
      tags = [ "example" ];
      
      features = {
        files = true;
        scripts = true;
      };
      
      panels = [
        {
          id = "my-extension-status";
          title = "My Extension";
          type = "PANEL_TYPE_STATUS";
          order = 1;
          fields = [
            {
              name = "metrics";
              type = "FIELD_TYPE_STRING";
              value = builtins.toJSON [
                { label = "Setting"; value = cfg.some-setting; status = "ok"; }
              ];
            }
          ];
        }
      ];
    };

    # Use core features
    stackpanel.files.entries."path/to/generated-file.ts" = {
      text = ''
        // Generated by my-extension
        export const setting = "${cfg.some-setting}";
      '';
    };

    stackpanel.scripts."my-extension:run" = {
      description = "Run my extension command";
      exec = ''
        echo "Running with setting: ${cfg.some-setting}"
      '';
    };

    stackpanel.devshell.packages = [ pkgs.some-tool ];

    stackpanel.motd.features = [ "My Extension" ];
  };
}
```

### 2. Add to Core Imports

Add the import to `nix/stackpanel/core/default.nix` or wherever modules are aggregated.

### 3. Create Proto Schema (Optional)

If your extension has user-editable data, create a proto schema:

```nix
# nix/stackpanel/db/schemas/my-extension.proto.nix
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "my_extension.proto";
  package = "stackpanel.db";
  
  messages = {
    MyExtension = proto.mkMessage {
      name = "MyExtension";
      fields = {
        enable = proto.bool 1 "Enable the extension";
        some_setting = proto.string 2 "A setting";
      };
    };
  };
}
```

## Extension Categories

Use categories to group extensions in the UI:

- `EXTENSION_CATEGORY_INFRASTRUCTURE` - AWS, cloud resources
- `EXTENSION_CATEGORY_CI_CD` - GitHub Actions, deployment pipelines
- `EXTENSION_CATEGORY_DATABASE` - Database management
- `EXTENSION_CATEGORY_SECRETS` - Secret/variable management
- `EXTENSION_CATEGORY_DEPLOYMENT` - Deployment tools
- `EXTENSION_CATEGORY_DEVELOPMENT` - Dev tools, linters
- `EXTENSION_CATEGORY_MONITORING` - Logging, metrics
- `EXTENSION_CATEGORY_INTEGRATION` - Third-party integrations

## Panel Types

Extensions can define UI panels:

- `PANEL_TYPE_STATUS` - Key-value status display
- `PANEL_TYPE_APPS_GRID` - Grid of applications
- `PANEL_TYPE_FORM` - Configuration form
- `PANEL_TYPE_TABLE` - Tabular data
- `PANEL_TYPE_CUSTOM` - Custom React component

## Accessing Extension Data

Extensions are exposed for the agent/web UI:

```nix
# In Nix
config.stackpanel.extensions        # All extensions
config.stackpanel.extensionsComputed # Only enabled extensions
config.stackpanel.extensionsBuiltin  # Only builtin extensions
config.stackpanel.extensionsExternal # Only external/local extensions
```

The agent can query extensions via the Nix evaluator and serve them to the web UI.

## Best Practices

1. **Use feature flags** - Declare which core features your extension uses
2. **Provide status panels** - Give users visibility into extension state
3. **Document requirements** - Use `stackpanel.moduleRequirements` to declare needed secrets/variables
4. **Keep options minimal** - Only expose what users need to configure
5. **Use sensible defaults** - Extensions should work with minimal configuration
6. **Register MOTD entries** - Help users discover commands and features