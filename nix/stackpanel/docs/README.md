# Docs Module

Documentation generation from Nix configuration.

## Overview

Generates project documentation (README.md) from templates at Nix evaluation time. Reads template files and populates them with data from the Stack configuration.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Module entry point |
| `readme.nix` | README.md generation from templates |

## Usage

```nix
stack.docs.readme = {
  enable = true;
  template = ./README.tmpl.md;  # optional custom template
};
```
