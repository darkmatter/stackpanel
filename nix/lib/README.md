# Stackpanel Nix Libraries

Reusable Nix libraries for development services, certificates, and AWS integration.

## Global Development Services

The `devshell.nix` library provides singleton development services that work across multiple projects. Services are shared (Postgres, Redis, Minio, Caddy) but each project can register its own databases and sites.

### Usage with `nix develop`

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    stackpanel.url = "github:darkmatter/stackpanel";
  };

  outputs = { self, nixpkgs, stackpanel, ... }:
    let
      system = "x86_64-linux"; # or "aarch64-darwin", etc.
      pkgs = nixpkgs.legacyPackages.${system};

      # Create dev services configuration
      devServices = stackpanel.lib.mkDevShell pkgs {
        projectName = "myproject";

        postgres = {
          enable = true;
          databases = ["myapp" "myapp_test"];
          port = 5432;  # optional, default 5432
        };

        redis.enable = true;
        minio.enable = true;

        caddy = {
          enable = true;
          sites = {
            "myapp.localhost" = "localhost:3000";
            "api.localhost" = "localhost:8080";
          };
        };
      };
    in {
      devShells.${system}.default = devServices.shell;
    };
}
```

### Merging with existing mkShell

```nix
devShells.${system}.default = pkgs.mkShell ({
  packages = devServices.packages ++ [
    pkgs.nodejs
    pkgs.bun
  ];

  shellHook = ''
    ${devServices.shellHook}
    echo "Welcome to my project!"
  '';
} // devServices.env);
```

### Usage with devenv

For devenv users, use the module instead:

```yaml
# devenv.yaml
inputs:
  stackpanel:
    url: github:darkmatter/stackpanel

imports:
  - stackpanel/nix/modules/devenv
```

```nix
# devenv.nix
{ pkgs, ... }: {
  stackpanel.globalServices = {
    enable = true;
    projectName = "myproject";

    postgres = {
      enable = true;
      databases = ["myapp" "myapp_test"];
    };

    redis.enable = true;
    minio.enable = true;
  };
}
```

## How Global Services Work

1. **Singleton Architecture**: Services store data in `~/.local/share/devservices/`
2. **Project Registration**: Each project registers its databases/sites on shell entry
3. **Shared Instances**: Multiple projects share the same Postgres, Redis, etc.
4. **CLI Management**: Use `stackpanel` CLI to manage all services

```bash
stackpanel status              # Show all service status
stackpanel services start      # Start all enabled services
stackpanel services stop       # Stop all services
stackpanel caddy add mysite    # Add a Caddy site
stackpanel certs ensure        # Get device certificate
```

## Other Libraries

| File | Purpose |
|------|---------|
| `services.nix` | Low-level service creation (Postgres, Redis, Minio) |
| `caddy.nix` | Caddy reverse proxy with Step CA integration |
| `aws.nix` | AWS IAM Roles Anywhere credential scripts |
| `network.nix` | Step CA certificate management |
