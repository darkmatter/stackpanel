# secrets/

SOPS-based secrets management - generates `.sops.yaml` and environment-specific secret files.

## Philosophy

**No new commands to learn.** Uses standard SOPS workflow:

- `sops secrets/dev.yaml` - edit dev secrets
- `sops exec-env secrets/dev.yaml './my-script.sh'` - run with secrets
- `git add secrets/*.yaml` - encrypted files safe to commit

## Files

| File | Purpose |
|------|---------|
| `default.nix` | Module entrypoint |
| `sops.nix` | SOPS config generation, environment-based access control |

## Generated Files

| File | Purpose |
|------|---------|
| `.sops.yaml` | SOPS configuration with AGE keys per environment |
| `secrets/{dev,staging,production}.yaml` | Environment-specific secrets (encrypted) |
| `secrets/common.yaml` | Shared secrets across environments |
| `secrets/.gitignore` | Ignores `*.local.yaml` overrides |

## Options

```nix
stackpanel.secrets = {
  enable = true;

  users = {
    alice = { pubkey = "age1..."; admin = true; };
    bob = { pubkey = "age1..."; };
    charlie = { pubkey = "age1..."; };
  };

  environments = {
    dev = { users = [ "alice" "bob" "charlie" ]; };
    staging = { users = [ "alice" "bob" ]; };
    production = {
      users = [ "alice" ];
      extraKeys = [ "age1..." ];  # CI system key
    };
  };
};
```

## Access Control

- **Admins** (`admin = true`) can decrypt ALL environments
- **Non-admins** can only decrypt environments they're listed in
- **extraKeys** for CI systems, servers, etc.

## Workflow

### Setup

1. Team members generate AGE keys: `age-keygen -o ~/.age/key.txt`
1. Share public keys: `age-keygen -y ~/.age/key.txt`
1. Agent syncs team → writes `.stackpanel/team.nix`
1. User configures environments in `flake.nix`
1. `nix run .#generate` creates `.sops.yaml` + placeholder files

### Daily Use

```bash
# Edit secrets
sops secrets/dev.yaml

# Run with secrets loaded
sops exec-env secrets/dev.yaml './start-server.sh'

# Local overrides (gitignored)
sops secrets/dev.local.yaml
```

### Adding Team Members

1. Get their AGE public key
1. Add to `stackpanel.secrets.users` in flake.nix
1. `nix run .#generate`
1. Re-encrypt: `sops updatekeys secrets/dev.yaml`

## Local Overrides

Create `secrets/{env}.local.yaml` for machine-specific secrets:

```bash
# Start from existing secrets
sops -d secrets/dev.yaml > secrets/dev.local.yaml
sops -e -i secrets/dev.local.yaml

# Use local version
sops exec-env secrets/dev.local.yaml './start.sh'
```

Local overrides are gitignored and won't be committed.

## TODO

- [] Auto-sync users from github
- [] Github action to re-key automatically
- [] Auto-generate KMS key, add as SOPS recipient (enables AWS SOPS Auth)
