# Caddy Library

Pure functions for managing a local Caddy reverse proxy.

## Overview

Provides pure helpers and scripts for Caddy lifecycle management, site
configuration, and Step CA TLS integration. Used by `services/caddy.nix` (the
NixOS module) and `apps/apps.nix` (for vhost registration).

Per-site Caddyfile snippets are generated **declaratively** via
`stackpanel.files.entries` (using `renderSite`) into each project's
`.stack/gen/caddy/` directory. The Go CLI (`stackpanel caddy add` / `remove`) only
symlinks those generated snippets into the shared `~/.config/caddy/sites.d/`;
it never writes them. This keeps site generation deterministic and pure.

## Functions

| Function                                                       | Description                                                                 |
| -------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `mkProjectPort { name }`                                       | Compute a stable port from project name                                     |
| `sanitizeDomain domain`                                        | Sanitize a domain into a filesystem-safe filename stem (matches the Go CLI) |
| `renderSite { domain, upstream, tls ? "" }`                    | Render a per-site Caddyfile snippet as a pure string                        |
| `mkCaddyScripts { stepEnabled, stepCaUrl, stepCaFingerprint }` | Generate all Caddy management scripts                                       |

## Scripts

| Script               | Description                     |
| -------------------- | ------------------------------- |
| `caddy-start`        | Start or reload Caddy           |
| `caddy-stop`         | Stop Caddy                      |
| `caddy-restart`      | Restart Caddy                   |
| `caddy-status`       | Check if Caddy is running       |
| `caddy-add-site`     | Add a virtual host              |
| `caddy-remove-site`  | Remove a virtual host           |
| `caddy-list-sites`   | List configured sites           |
| `caddy-project-port` | Get project port from directory |
