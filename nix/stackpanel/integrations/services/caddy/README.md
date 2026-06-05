# Caddy Library

Pure functions for managing a local Caddy reverse proxy.

## Overview

Provides scripts for Caddy lifecycle management, site configuration, and Step CA TLS integration. Used by `services/caddy.nix` (the NixOS module) and `apps/apps.nix` (for vhost registration).

## Functions

| Function | Description |
|----------|-------------|
| `mkProjectPort { name }` | Compute a stable port from project name |
| `mkCaddyScripts { stepEnabled, stepCaUrl, stepCaFingerprint }` | Generate all Caddy management scripts |

## Scripts

| Script | Description |
|--------|-------------|
| `caddy-start` | Start or reload Caddy |
| `caddy-stop` | Stop Caddy |
| `caddy-restart` | Restart Caddy |
| `caddy-status` | Check if Caddy is running |
| `caddy-add-site` | Add a virtual host |
| `caddy-remove-site` | Remove a virtual host |
| `caddy-list-sites` | List configured sites |
| `caddy-project-port` | Get project port from directory |
