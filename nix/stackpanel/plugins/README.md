# Plugins

Auto-discovered feature modules that extend Stack.

## Overview

Each subdirectory is automatically imported as a Stack plugin. Plugins follow a standard structure with metadata, module logic, and optional UI panels.

## Plugin Structure

```
plugins/
├── _template/          # Template for creating new plugins
├── bun/                # Bun runtime integration
├── go/                 # Go toolchain and app module
├── turbo/              # Turborepo task management
├── oxlint/             # OxLint code quality
├── process-compose/    # Process orchestration
├── git-hooks/          # Git hooks via pre-commit
├── ci-formatters/      # CI formatter integration
├── app-commands/       # Per-app dev/build/test commands
├── entrypoints/        # Container entrypoint generation
└── env-codegen/        # Environment variable codegen
```

## Creating a Plugin

Copy `_template/` and implement the standard files:

| File | Required | Description |
|------|----------|-------------|
| `default.nix` | Yes | Entry point — imports all other files |
| `meta.nix` | Yes | Plugin metadata (name, category, icon) for fast discovery |
| `module.nix` | Yes | Options, config, and logic |
| `ui.nix` | No | Web studio panel definitions |
| `schema.nix` | No | Proto-derived per-app options |

## Discovery

Plugins are auto-imported by `default.nix` which scans subdirectories (excluding `_*` and `.*` prefixes). Plugin metadata is read from `meta.nix` without evaluating the full module, enabling fast discovery.
