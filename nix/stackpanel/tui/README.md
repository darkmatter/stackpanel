# TUI Module

Terminal User Interface customization for development shells.

## Overview

This module provides terminal theming and prompt customization for development environments. Currently focuses on Starship prompt configuration with plans for interactive TUI features.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Module entry point and imports |
| `theme.nix` | Starship prompt configuration |
| `starship.toml` | Default Starship theme configuration |

## Starship Prompt

The theme module configures [Starship](https://starship.rs/) prompt for consistent terminal experience across the team.

### Features

- Git status and branch display
- Current directory with truncation
- Language version indicators (Node, Python, Rust, etc.)
- Command duration for long-running tasks
- Custom stack styling

### Usage

```nix
# devenv.nix
stack.theme = {
  enable = true;
  # Optional: use custom config
  config-file = ./my-starship.toml;
};
```

## Direnv Compatibility

The theme module is direnv-aware and avoids double-initialization:

- In direct `devenv shell`: Starship is initialized automatically
- With direnv: Relies on user's shell rc file for starship init

## Custom Themes

To use a custom Starship configuration:

1. Create a `starship.toml` file with your preferences
2. Reference it in the config:

```nix
stack.theme.config-file = ./config/starship.toml;
```

## Future Features

Planned TUI enhancements:

- Interactive service management dashboard
- Log viewer with filtering
- Configuration wizard
- Status overview panel
