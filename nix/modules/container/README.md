# container/

Container image generation - Dockerfile, docker-compose, and registry configuration.

## Files

| File | Purpose |
|------|---------|
| `default.nix` | Module entrypoint (scaffold) |

## Planned Options

```nix
stackpanel.container = {
  enable = true;

  # Auto-detect or specify
  baseImage = "node:20-slim";  # or auto-detect from project

  # Multi-stage build
  stages = {
    build = { /* ... */ };
    runtime = { /* ... */ };
  };

  # Or use Nix-based images
  nixBased = {
    enable = true;
    # Uses dockerTools.buildImage
  };

  # Docker compose for local dev
  compose = {
    enable = true;
    services = {
      app = { /* ... */ };
      db = { image = "postgres:16"; };
    };
  };
};
```

## Generated Files

- `Dockerfile` - multi-stage optimized build
- `docker-compose.yml` - local development services
- `.dockerignore` - exclude unnecessary files

## TODO

- [ ] nix2container generation
- [ ] Auto-detect project type (Node, Go, Python, etc.)
- [ ] Generate optimized Dockerfile per stack
- [ ] Docker compose generation
- [ ] Registry authentication
- [ ] Nix-based images (dockerTools)
- [ ] Health checks
- [ ] Security scanning integration
