# Deployment

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
stackpanel.apps.api = {
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
stackpanel.containers.api = {
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
stackpanel.apps.api = {
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

See the full [deployment documentation](https://stackpanel.dev/docs/deployment) for more details.