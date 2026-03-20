# Cloudflare Deployment Provider

Deploy apps as [Cloudflare Workers](https://developers.cloudflare.com/workers/) or Pages via Alchemy IaC.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Entry point |
| `module.nix` | Per-app deployment options and config generation |
| `schema.nix` | Proto-derived Cloudflare config schema |
| `ui.nix` | Web studio panel |

## Usage

```nix
stack.apps.web.deployment = {
  enable = true;
  provider = "cloudflare";
  cloudflare = {
    workerName = "my-web-app";
    type = "vite";       # vite, worker, or pages
    route = "example.com/*";
  };
};
```
