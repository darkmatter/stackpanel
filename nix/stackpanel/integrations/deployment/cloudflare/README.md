# Cloudflare Deployment Provider

Deploy apps as [Cloudflare Workers](https://developers.cloudflare.com/workers/) or Pages via Alchemy IaC.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Entry point |
| `module.nix` | Per-app deployment options and config generation |
| `schema.nix` | Runtime SpFields shared by app options and Studio |
| `ui.nix` | Web studio panel |

## Usage

```nix
stackpanel.apps.web.deployment = {
  enable = true;
  backend = "alchemy";
  host = "cloudflare";
  cloudflare = {
    workerName = "my-web-app";
    route = "app.example.com/*";
  };
};
```

`cloudflare` is the default `stackpanel.deployment.defaultHost`. Other modules can
register hosts and backends without changing the deployment options. The
`deployment-cloudflare` module remains discoverable even without matching apps;
its per-app panel appears in the deployment tab for Cloudflare apps.
