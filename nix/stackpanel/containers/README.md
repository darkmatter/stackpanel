# Containers Module

OCI container image building with nix2container or dockerTools.

## Overview

Builds container images for apps using either [nix2container](https://github.com/nlewo/nix2container) (default, layer-optimized) or nixpkgs `dockerTools`. Supports per-app container configuration and direct image definitions.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Module entry point |
| `module.nix` | Container options and build logic |
| `builder.nix` | Backend-specific image builders |
| `schema.nix` | Proto-derived container config schema |
| `ui.nix` | Web studio panel definitions |
| `meta.nix` | Module metadata |

## Usage

```nix
# Per-app containers
stack.apps.web.container = {
  enable = true;
  type = "bun";
  port = 3000;
};

# Or direct image definitions
stack.containers.images.my-image = {
  name = "my-app";
  type = "bun";
  port = 3000;
};
```

## Commands

| Command | Description |
|---------|-------------|
| `container-build <name>` | Build a container image |
| `container-copy <name>` | Build and push to registry |
| `container-run <name>` | Build and run locally |
