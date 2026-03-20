# Stack Example Templates

This directory contains review-friendly templates that are compatible with `nix flake init -t`.

Available examples:

- `example-basic` - single app starter
- `example-multi-app` - monorepo with multiple apps and shared services
- `example-cloudflare` - edge-focused deployment configuration

Use from this repository:

```bash
nix flake init -t .#example-basic
nix flake init -t .#example-multi-app
nix flake init -t .#example-cloudflare
```

Use from GitHub:

```bash
nix flake init -t github:darkmatter/stack#example-basic
nix flake init -t github:darkmatter/stack#example-multi-app
nix flake init -t github:darkmatter/stack#example-cloudflare
```
