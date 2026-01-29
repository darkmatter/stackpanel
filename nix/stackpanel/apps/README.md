# Apps Module

Application port management and Caddy virtual host configuration for devenv.

## Overview

This module provides a unified way to manage application ports and domains in development environments. Each app gets a deterministic port based on the project name and can optionally be assigned a domain with automatic Caddy vhost setup.

## Domain Format

Virtual hosts use the format: `<app>.<project>.<tld>`

Examples:
- `web.myproject.localhost` (default TLD)
- `api.myproject.lan` (custom TLD)

The TLD is configured via `stackpanel.caddy.tld` (default: `"localhost"`).

## Files

| File | Description |
|------|-------------|
| `apps.nix` | Application port assignment and Caddy vhost integration |
| `ci.nix` | GitHub Actions CI/CD workflow generation |

## Port Layout

Ports are computed from a base port (derived from project name):

- **+0 to +9**: User apps (web, server, docs, etc.)
- **+10 to +99**: Infrastructure services (postgres, redis, minio)

## Usage

```nix
# devenv.nix
stackpanel.apps = {
  web = {};                          # Just port (basePort + 0)
  server = { offset = 1; };          # Port with explicit offset
  docs = { domain = "docs"; };       # Port + docs.<project>.localhost vhost
  api = {
    domain = "api";
    tls = true;                      # Use TLS (requires Step CA)
  };
};

# To use a custom TLD (e.g., .lan):
stackpanel.caddy.tld = "lan";
```

## Environment Variables

Apps automatically generate environment variables:

- `$PORT_WEB`, `$PORT_SERVER`, etc. - Port numbers
- `$URL_DOCS`, `$URL_API` - Full URLs for apps with domains

## CI Integration

Generate GitHub Actions workflows declaratively:

```nix
stackpanel.ci.github = {
  enable = true;
  checks = {
    enable = true;
    branches = ["main"];
    commands = ["nix flake check"];
  };
};
```
