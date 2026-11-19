# Deployment

## Web and docs previews

Both GitHub Actions deployments use the Alchemy stack in the app directory and the `pr-<number>` stage. They store preview resource IDs in the same Cloudflare state service used by staging and production, so closing a PR can destroy the right resources. Local `dev` uses the filesystem instead.

The app's `--yes` approves its own resource plan, **not** changes to the shared state service. In CI, `selectStateBackend` disables Alchemy's automatic store provisioning for both deploy and destroy. If the store is missing or its protocol changes, update the workspace's Alchemy client and provider packages together or coordinate a separate store operation with the account owner. Do not reset the store or rotate its keys to repair a preview.

## Building Containers

Build OCI-compatible container images for your apps:

```bash
# Build a container for a specific app
nix build --impure ".#packages.x86_64-linux.container-<app-name>"

# Example: build container for an app named "api"
nix build --impure ".#packages.x86_64-linux.container-api"

# Load into Docker
docker load < result

# Or use the convenience script
container-build <app-name>
```

## Configuration

Define containers in your `flake.nix`:

```nix
stack.apps.api = {
  port = 1;
  root = "./apps/api";
  build = "bun run build";
  
  container = {
    enable = true;
    entrypoint = [ "${pkgs.bun}/bin/bun" "run" "dist/index.js" ];
  };
};
```

Or define them separately:

```nix
stack.containers.api = {
  enable = true;
  name = "myapp-api";
  tag = "latest";
  
  config = {
    entrypoint = [ "${pkgs.bun}/bin/bun" "run" "dist/index.js" ];
    env = {
      NODE_ENV = "production";
    };
  };
};
```

## Deployment Targets

Configure deployment for your apps:

```nix
stack.apps.api = {
  port = 1;
  root = "./apps/api";
  
  deployment = {
    enable = true;
    host = "fly";  # or "cloudflare", "vercel", "aws"
    
    fly = {
      appName = "myapp-api";
      region = "iad";
      memory = "512mb";
      cpus = 1;
    };
  };
};
```

See the full [deployment documentation](https://stack.dev/docs/deployment) for more details.