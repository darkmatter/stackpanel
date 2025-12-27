# Stackpanel Services

This directory contains service configuration utilities and definitions for development infrastructure services.

## Overview

The services module provides:

- **Port computation**: Deterministic port assignment based on project name
- **Service definitions**: PostgreSQL, Redis, Minio with lifecycle management
- **Global services**: Singleton service configuration shared across projects

## Files

| File | Description |
|------|-------------|
| `default.nix` | Core library exports (ports, globalServices, services) |
| `ports.nix` | Pure port computation functions |
| `services.nix` | Service registry and factory |
| `global-services.nix` | Global singleton service configuration |
| `postgres.nix` | PostgreSQL service definition |
| `redis.nix` | Redis service definition |
| `minio.nix` | Minio (S3) service definition |

## Port Computation

Ports are computed deterministically from project name using MD5 hashing:

```nix
let portsLib = import ./ports.nix { inherit lib; };
in portsLib.computeBasePort { name = "myproject"; }
# Returns something like 3500 (rounded to modulus 100)
```

### Port Layout

From the base port:
- **+0 to +9**: User applications (web, api, docs, etc.)
- **+10 to +99**: Infrastructure services (postgres, redis, minio, etc.)

### Available Functions

```nix
portsLib.computeBasePort { name, minPort?, portRange?, modulus? }
portsLib.computeServicePort { basePort, index, servicesBaseOffset? }
portsLib.computeServicesWithPorts { basePort, services, servicesBaseOffset? }
portsLib.mkServicesByKey servicesWithPorts
portsLib.mkServiceEnvVars servicesWithPorts
portsLib.mkPortsConfig { projectName, services?, ... }
```

## Service Registry

Services are defined in individual files and registered in `services.nix`:

```nix
let servicesLib = import ./services.nix { inherit pkgs lib; };
in servicesLib.mkService "postgres" {
  projectName = "myapp";
  port = 5432;
  databases = ["myapp" "myapp_test"];
}
```

### Available Services

- **postgres**: PostgreSQL database with per-project databases
- **redis**: Redis key-value store
- **minio**: S3-compatible object storage

### Service Data Location

Services store data in project-local directories by default:
```
<projectRoot>/.stackpanel/state/services/<service>/
```

This allows different projects to have isolated service data.

## Global Services

Global services run as singletons shared across all projects:

```nix
let globalServices = import ./global-services.nix { inherit pkgs lib; };
in globalServices.mkGlobalServices {
  projectName = "myapp";
  postgres = {
    enable = true;
    databases = ["myapp"];
  };
  redis.enable = true;
}
```

### Why Global?

Some services benefit from global instances:
- **Caddy**: Must bind to ports 80/443, can't have multiple instances
- **PostgreSQL**: Heavy to start; shared instance with per-project databases
- **Redis**: Lightweight but convenient to share

### Returns

`mkGlobalServices` returns:
- `packages`: List of packages to add to shell
- `shellHook`: Initialization script
- `env`: Environment variables (DATABASE_URL, REDIS_URL, etc.)
- `services`: Individual service objects for advanced use

## Adding New Services

1. Create `<service>.nix` following the pattern:

```nix
{ pkgs, lib, baseDir }:
{
  mkService = { projectName, port ? 1234, ... }: {
    name = "myservice";
    displayName = "My Service";
    port = port;
    env = { MY_SERVICE_PORT = toString port; };
    allPackages = [ pkgs.myservice ];
    shellHook = ''
      # Initialization script
    '';
  };
}
```

2. Register in `services.nix`:

```nix
serviceModules = {
  postgres = postgresModule;
  redis = redisModule;
  minio = minioModule;
  myservice = myserviceModule;  # Add this
};
```

3. Add default port in `services.nix`:

```nix
defaultPorts = {
  postgres = 5432;
  redis = 6379;
  minio = 9000;
  myservice = 1234;  # Add this
};
```
