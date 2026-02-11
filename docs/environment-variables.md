# Stackpanel Environment Variables Reference

This document provides a comprehensive reference for all environment variables used by Stackpanel.

> **Source of Truth**: The authoritative definitions are in:
> - Nix: `nix/stackpanel/core/lib/envvars.nix`
> - Go: `packages/stackpanel-go/envvars/envvars.go`

## Quick Reference

| Variable | Description | Required |
|----------|-------------|----------|
| `STACKPANEL_ROOT` | Project root directory | ✓ |
| `STACKPANEL_STATE_DIR` | State directory | ✓ |
| `STACKPANEL_STATE_FILE` | Path to state file | |
| `STACKPANEL_GEN_DIR` | Generated files directory | |
| `STACKPANEL_NIX_CONFIG` | Source Nix config file path | |
| `STACKPANEL_CONFIG_JSON` | Nix-generated config JSON in store | |
| `STACKPANEL_STABLE_PORT` | Base port for the project | |
| `STACKPANEL_SERVICES_CONFIG` | JSON array of service definitions | |

## CLI Commands

Use the `stackpanel env` command to inspect and validate environment variables:

```bash
# List all environment variables
stackpanel env list

# Show current values
stackpanel env list --values

# Filter by category
stackpanel env list --category aws

# Show only missing required variables
stackpanel env list --missing

# Validate required variables
stackpanel env validate

# Get details about a specific variable
stackpanel env get STACKPANEL_ROOT

# Debug view of all variables
stackpanel env debug
```

---

## Core Stackpanel

### `STACKPANEL_ROOT`

Absolute path to the project root directory.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | Yes |
| Example | `/home/user/my-project` |

This is the primary variable used to locate the project. It's set automatically when entering a devenv shell.

### `STACKPANEL_ROOT_DIR_NAME`

Name of the .stackpanel directory within the project.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Default | `.stackpanel` |

### `STACKPANEL_SHELL_ID`

Unique identifier for the current shell session.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Default | `1` |

Used to differentiate between multiple concurrent shell sessions.

### `STACKPANEL_NIX_CONFIG`

Path to the source Nix config file (`.stackpanel/config.nix`).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `/home/user/my-project/.stackpanel/config.nix` |

This points to the source Nix configuration file that users edit. Use this for `nix eval` or `import` operations that need to evaluate the live configuration.

### `STACKPANEL_CONFIG_JSON`

Path to the Nix-generated config JSON in the Nix store.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `/nix/store/xxx-stackpanel-config.json` |

This is set by the devenv shell hook and points to the pre-computed JSON configuration generated at shell entry time. The Go CLI uses this for fast config access without needing to evaluate Nix.

---

## Paths & Directories

### `STACKPANEL_STATE_DIR`

Directory for runtime state (credentials, caches, etc.).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | Yes |
| Example | `/home/user/my-project/.stackpanel/state` |

Contains:
- `stackpanel.json` - Runtime state file
- `step/` - Step CA certificates and keys
- `aws/` - AWS credential cache

### `STACKPANEL_STATE_FILE`

Full path to the stackpanel.json state file.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `/home/user/my-project/.stackpanel/state/stackpanel.json` |

Derived from `STACKPANEL_STATE_DIR` + `/stackpanel.json`.

### `STACKPANEL_GEN_DIR`

Directory for generated files (configs, scripts).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `/home/user/my-project/.stackpanel/gen` |

Contains generated configuration files like:
- VS Code workspace settings
- Caddy configurations
- Generated scripts

### `STACKPANEL_DATA_DIR`

Directory for persistent data (databases, etc.).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `/home/user/my-project/.stackpanel/data` |

---

## Stackpanel Agent

These variables configure the Stackpanel agent when it's spawned externally (e.g., from an IDE or CI).

### `STACKPANEL_PROJECT_ROOT`

Project root override for the agent (when spawned externally).

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

Overrides `STACKPANEL_ROOT` when the agent is started by an external process.

### `STACKPANEL_AUTH_TOKEN`

Authentication token for the agent API.

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

Used to secure the agent API when exposed over the network.

### `STACKPANEL_API_ENDPOINT`

API endpoint URL for the agent.

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |
| Default | `http://localhost:6401` |

---

## Step CA (Certificates)

These variables configure the Step CA integration for local TLS certificates.

### `STEP_CA_URL`

URL of the Step CA server.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `https://ca.internal:443` |

### `STEP_CA_FINGERPRINT`

SHA256 fingerprint of the Step CA root certificate.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a` |

Used to verify the Step CA server's identity when bootstrapping.

---

## AWS & Roles Anywhere

These variables configure AWS Roles Anywhere authentication using X.509 certificates.

### `AWS_TRUST_ANCHOR_ARN`

ARN of the IAM Roles Anywhere trust anchor.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/abc123` |

### `AWS_PROFILE_ARN`

ARN of the IAM Roles Anywhere profile.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `arn:aws:rolesanywhere:us-east-1:123456789012:profile/def456` |

### `AWS_ROLE_ARN`

ARN of the IAM role to assume via Roles Anywhere.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `arn:aws:iam::123456789012:role/DeveloperRole` |

### `AWS_REGION`

Default AWS region for API calls.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Default | `us-east-1` |

### `AWS_ACCESS_KEY_ID`

AWS access key ID (set dynamically by credential scripts).

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

Set automatically by `aws-creds-env` script when using Roles Anywhere.

### `AWS_SECRET_ACCESS_KEY`

AWS secret access key (set dynamically by credential scripts).

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

### `AWS_SESSION_TOKEN`

AWS session token for temporary credentials.

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

### `AWS_SHARED_CREDENTIALS_FILE`

Path to AWS credentials file.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Default | `/dev/null` |

Set to `/dev/null` to force using Roles Anywhere instead of static credentials.

### `AWS_CERT_PATH`

Override path to device certificate for Roles Anywhere.

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

Defaults to `$STACKPANEL_STATE_DIR/step/device-root.chain.crt`.

### `AWS_KEY_PATH`

Override path to device private key for Roles Anywhere.

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

Defaults to `$STACKPANEL_STATE_DIR/step/device.key`.

### `AWS_SIGNING_HELPER`

Override path to aws_signing_helper binary.

| Property | Value |
|----------|-------|
| Source | dynamic |
| Required | No |

---

## MinIO (S3-Compatible Storage)

These variables configure the MinIO local S3-compatible storage service.

> **Note**: We intentionally don't set `AWS_ENDPOINT_URL` or `AWS_*` credentials globally because it would break AWS IAM authentication. Apps should use `MINIO_ENDPOINT` and `S3_ENDPOINT` for MinIO access.

### `MINIO_ROOT_USER`

MinIO admin username.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Default | `minioadmin` |

### `MINIO_ROOT_PASSWORD`

MinIO admin password.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Default | `minioadmin` |

### `MINIO_ENDPOINT`

MinIO S3 endpoint URL.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `http://localhost:9000` |

### `MINIO_ACCESS_KEY`

MinIO access key (alias for MINIO_ROOT_USER).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |

### `MINIO_SECRET_KEY`

MinIO secret key (alias for MINIO_ROOT_PASSWORD).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |

### `MINIO_CONSOLE_ADDRESS`

MinIO console bind address.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `:9001` |

### `S3_ENDPOINT`

S3-compatible endpoint URL (points to MinIO when enabled).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `http://localhost:9000` |

---

## Services Config

Service ports are exposed via a JSON payload instead of per-service environment variables.

### `STACKPANEL_STABLE_PORT`

Base port for the project (index 0 in the port layout).

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `6400` |

### `STACKPANEL_SERVICES_CONFIG`

JSON array of service definitions with ports.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Example | `[{"key":"POSTGRES","name":"PostgreSQL","port":6410}]` |

### Configuring Ports

In your `devenv.nix`:

```nix
stackpanel.ports.services = [
  { key = "POSTGRES"; name = "PostgreSQL"; }
  { key = "REDIS"; name = "Redis"; }
  { key = "MINIO"; name = "Minio"; }
  { key = "MINIO_CONSOLE"; name = "Minio Console"; }
];
```

Each service gets a port at `basePort + 10 + index`, which is available in `STACKPANEL_SERVICES_CONFIG`.

---

## Devenv Integration

These variables are set by devenv itself and are available for reference.

### `DEVENV_ROOT`

Root directory of the devenv project (set by devenv).

| Property | Value |
|----------|-------|
| Source | devenv |
| Required | No |

### `DEVENV_STATE`

State directory for devenv (set by devenv).

| Property | Value |
|----------|-------|
| Source | devenv |
| Required | No |

### `DEVENV_DOTFILE`

Path to devenv dotfile directory.

| Property | Value |
|----------|-------|
| Source | devenv |
| Required | No |

### `DEVENV_PROFILE`

Current devenv profile path.

| Property | Value |
|----------|-------|
| Source | devenv |
| Required | No |

---

## IDE Integration

### `DEVENV_VSCODE_SHELL`

Marker to prevent shell recursion in VS Code.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |

Set to `1` when inside a VS Code integrated terminal to prevent infinite recursion when VS Code starts a new shell.

### `EDITOR`

Default text editor.

| Property | Value |
|----------|-------|
| Source | nix |
| Required | No |
| Default | `vim` |

---

## Troubleshooting

### Missing Required Variables

If you see errors about missing required variables:

1. Ensure you're inside a devenv shell:
   ```bash
   devenv shell
   ```

2. Verify the shell hooks ran successfully:
   ```bash
   stackpanel env validate
   ```

3. Check for specific missing variables:
   ```bash
   stackpanel env list --missing
   ```

### AWS Credentials Not Working

1. Verify Step CA certificates exist:
   ```bash
   ls -la $STACKPANEL_STATE_DIR/step/
   ```

2. Check Roles Anywhere configuration:
   ```bash
   stackpanel env list --category aws --values
   ```

3. Test credential fetching:
   ```bash
   aws-creds-env
   ```

### Port Conflicts

Check which ports are configured:
```bash
stackpanel env list --category services --values
```

### Debugging

For a complete debug dump:
```bash
stackpanel env debug
```

---

## Adding New Variables

When adding new environment variables:

1. **Update Nix definitions** in `nix/stackpanel/core/lib/envvars.nix`
2. **Update Go definitions** in `packages/stackpanel-go/envvars/envvars.go`
3. **Update this documentation**

Both files should stay in sync to ensure consistent behavior between Nix and Go code.
