# Deployment Module

Deployment providers for shipping apps to production.

## Overview

Aggregates deployment providers (Fly.io, Cloudflare Workers) with per-app configuration. Each app can specify its deployment target, and the module generates the necessary config files and scripts.

## Providers

| Provider | Directory | Description |
|----------|-----------|-------------|
| Fly.io | `fly/` | Container-based deployment with `fly.toml` generation |
| Cloudflare | `cloudflare/` | Workers/Pages deployment via Alchemy IaC |

## Usage

```nix
stack.deployment.defaultProvider = "fly";

stack.apps.web.deployment = {
  enable = true;
  provider = "fly";
  fly.appName = "my-web-app";
  fly.region = "iad";
  container = { type = "bun"; port = 3000; };
};

stack.apps.api.deployment = {
  enable = true;
  provider = "cloudflare";
  cloudflare = { workerName = "my-api"; type = "worker"; };
};
```
