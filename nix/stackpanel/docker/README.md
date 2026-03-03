# Docker Module

Container tooling and OCI image references.

## Overview

Provides [skopeo](https://github.com/containers/skopeo) for OCI image operations (copy, inspect, list tags) and manages image reference definitions. Does not build images — see the `containers/` module for that.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Module entry point |
| `module.nix` | Docker options and skopeo integration |
| `meta.nix` | Module metadata |

## Usage

```nix
stackpanel.docker = {
  enable = true;
  images.my-app = {
    name = "my-app";
    tag = "latest";
    registry = "ghcr.io/my-org";
  };
};
```
