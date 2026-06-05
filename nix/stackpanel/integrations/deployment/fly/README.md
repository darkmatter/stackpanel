# Fly.io Deployment Provider

Container-based deployment to [Fly.io](https://fly.io) with generated `fly.toml`.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Entry point |
| `module.nix` | Per-app deployment options and config generation |
| `schema.nix` | Proto-derived Fly.io config schema |
| `ui.nix` | Web studio panel |

Container builds for Fly-deployed apps are produced by
`stackpanel.containers` (see `nix/stackpanel/containers/`) — this module
just contributes per-app entries to `stackpanel.containers.images`. The
shared `flyOidc` helpers live at `nix/stackpanel/lib/services/fly-oidc.nix`
and are re-exported as `inputs.stackpanel.lib.flyOidc`.

## Usage

```nix
stack.apps.web.deployment = {
  enable = true;
  provider = "fly";
  fly = {
    appName = "my-web-app";
    region = "iad";
    memory = 256;
    minMachines = 1;
  };
  container = { type = "bun"; port = 3000; };
};
```
