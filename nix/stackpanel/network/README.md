# Network Module

Step CA certificate management and port assignment for development environments.

## Overview

This module handles network-related configuration including:

- **Step CA Integration**: Automatic device certificate provisioning
- **Port Management**: Deterministic port assignment based on project name

## Files

| File | Description |
|------|-------------|
| `network.nix` | Step CA certificate management and setup |
| `ports.nix` | Deterministic port computation and environment variables |

## Step CA Integration

Step CA provides secure TLS certificates for internal services. With a device certificate, you can:

- Access internal APIs and services securely
- Authenticate to AWS using Roles Anywhere
- Connect to databases without passwords

### Usage

```nix
# devenv.nix
stackpanel.network.step = {
  enable = true;
  ca-url = "https://ca.internal:443";
  ca-fingerprint = "abc123...";
  provisioner = "developer";
};
```

### Commands

- `ensure-device-cert` - Request or renew device certificate
- `check-device-cert` - Verify certificate status

## Port Assignment

Ports are computed from a hash of the project name, ensuring consistent ports across machines.

### Port Layout

| Offset | Purpose |
|--------|---------|
| +0 to +9 | User apps (web, server, docs) |
| +10 to +99 | Infrastructure services (postgres, redis, minio) |

### Environment Variables

- `STACKPANEL_BASE_PORT` - The computed base port
- `PORT_POSTGRES`, `PORT_REDIS`, etc. - Service-specific ports

### Example

```
projectName = "myapp" -> basePort = 3100
├── Web app: 3100
├── Server: 3101
├── Docs: 3102
├── PostgreSQL: 3110
├── Redis: 3111
└── Minio: 3112
```
