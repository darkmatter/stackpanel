# My Project

Powered by [stackpanel](https://github.com/stack-panel/nix).

## Getting Started

```bash
# Enter dev environment
direnv allow
# or
nix develop

# Generate managed files
nix run .#generate

# Preview what would be generated
nix run .#generate-diff
```

## Secrets

Secrets are managed via agenix. To add a new secret:

```bash
cd secrets
agenix -e my-secret.age
```

Then add it to `flake.nix`:

```nix
stackpanel.secrets.secrets."my-secret.age".owners = [ "alice" ];
```
