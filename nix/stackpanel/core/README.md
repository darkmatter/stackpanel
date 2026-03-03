# Core Module

Foundational options and boot logic for the Stackpanel module system.

## Overview

The core module defines the root configuration schema (project name, directories, root marker) and sets up the devshell environment: environment variables, directory creation, shell hooks, and CLI integration.

Feature-specific options live in their own directories (`apps/`, `services/`, `network/`, `secrets/`, `ide/`, `tui/`, `variables/`).

## Files

| File | Description |
|------|-------------|
| `default.nix` | Entry point — imports all core modules, sets up hooks |
| `options-core.nix` | Root options: enable, name, root, dirs, direnv, git-hooks, checks |
| `outputs.nix` | Flake output derivations and apps |
| `checks.nix` | Module check schema for `nix flake check` |
| `motd.nix` | Message of the Day configuration |
| `codegen.nix` | Code generator definitions |
| `cli.nix` | CLI-based file generation (invokes Go CLI) |
| `cli-options.nix` | CLI enable/quiet options |
| `state.nix` | Legacy state file generation |
| `state-options.nix` | State file options |
| `user-packages.nix` | User-installed packages from `.stackpanel/data/packages.nix` |
| `users-options.nix` | Team member definitions |
| `panels.nix` | UI panel system for the web studio |
| `tasks.nix` | Turborepo task definitions |
| `ci.nix` | CI/CD workflow generation |
| `modules-options.nix` | Module registry schema |
| `extensions.nix` | Extension system (backward compat alias to modules) |
| `aliases.nix` | Shell alias management |
| `util.nix` | Internal logging utilities |

## Usage

The core module is imported automatically via `nix/stackpanel/default.nix`. Configure it in your project:

```nix
stackpanel = {
  enable = true;
  name = "my-project";
  dirs.home = ".stackpanel";
};
```
