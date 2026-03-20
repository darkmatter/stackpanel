# Stack Options Schema

This directory contains all option definitions for the Stack module system. These are **pure option declarations** - they define the schema and types, but contain no implementation logic.

## Overview

Options are organized by feature area:

| File | Description |
|------|-------------|
| `core.nix` | Root paths, directories, basic settings |
| `apps.nix` | Application port and domain configuration |
| `ports.nix` | Deterministic port computation |
| `devshell.nix` | Shell environment (packages, hooks, commands, files) |
| `global-services.nix` | PostgreSQL, Redis, Minio, Caddy services |
| `caddy.nix` | Caddy reverse proxy configuration |
| `network.nix` | Step CA certificate management |
| `aws.nix` | AWS Roles Anywhere certificate auth |
| `ide.nix` | VS Code, Zed, Cursor integration |
| `secrets.nix` | SOPS-encrypted secrets management |
| `cli.nix` | CLI behavior options |
| `codegen.nix` | Code generator definitions |
| `ci.nix` | CI/CD workflow generation |
| `motd.nix` | Message of the Day help display |
| `theme.nix` | Starship prompt theming |

## Option Namespaces

All options are under the `stack` namespace:

```nix
stack.enable           # Master switch
stack.root             # Project root path
stack.dirs.*           # Directory configuration
stack.apps.*           # Application definitions
stack.ports.*          # Port configuration
stack.devshell.*       # Shell environment
stack.globalServices.* # Development services
stack.network.*        # Network/TLS settings
stack.secrets.*        # Secrets management
stack.ide.*            # IDE integration
stack.cli.*            # CLI settings
stack.motd.*           # Help message
stack.theme.*          # Prompt theming
```

## Design Principles

### Pure Declarations

Option files contain only `lib.mkOption` declarations. No implementation logic, no `config = ...` blocks. This allows the schema to be:
- Evaluated without side effects
- Used for documentation generation
- Validated independently of implementation

### Adapter-Agnostic

Options work with any Nix module system:
- devenv
- NixOS modules
- flake-parts
- `lib.evalModules`

Implementation is provided by adapter modules that translate options to the target system.

### Hierarchical Types

Complex options use `lib.types.submodule` for nested configuration:

```nix
options.stack.apps = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      offset = lib.mkOption { ... };
      domain = lib.mkOption { ... };
      tls = lib.mkOption { ... };
    };
  });
};
```

### Computed Values

Read-only options expose computed values:

```nix
options.stack.ports.base-port = lib.mkOption {
  type = lib.types.port;
  readOnly = true;
  default = basePort;  # Computed from project-name
};
```

## Adding New Options

1. Create a new file following the naming convention: `<feature>.nix`
2. Use the standard header format (see existing files)
3. Define options under `options.stack.<feature>`
4. Import the file in `default.nix`
5. Implement the feature in the appropriate core module

Example template:

```nix
# ==============================================================================
# myfeature.nix
#
# Brief description of what this feature does.
#
# Detailed explanation of options, usage examples, etc.
# ==============================================================================
{ lib, ... }: {
  options.stack.myfeature = {
    enable = lib.mkEnableOption "My feature description";

    setting = lib.mkOption {
      type = lib.types.str;
      default = "default-value";
      description = "What this setting controls";
      example = "example-value";
    };
  };
}
```
