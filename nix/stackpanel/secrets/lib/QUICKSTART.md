# Quick Start: Age Key Management

Get started with age key management in Stackpanel projects in under 5 minutes.

## TL;DR

```bash
# 1. Fetch your age keys from 1Password
age:fetch

# 2. Check they're available
age:check

# 3. Use SOPS as normal
sops .stack/secrets/dev/web.sops.yaml
```

That's it! If you're already set up, skip to [Usage](#usage).

## Setup

### For New Projects

Add to your Stackpanel configuration:

```nix
{
  imports = [
    ./nix/stackpanel/secrets/lib/age-key-cmd.nix
  ];

  stackpanel.secrets.age-key-cmd.enable = true;
}
```

Enter your dev shell:

```bash
nix develop
```

### For Existing Projects

If your project is already configured, just enter the dev shell:

```bash
nix develop
```

The age key tools are automatically available.

## First Time Setup

### 1. Authenticate with 1Password

```bash
op signin
```

### 2. Fetch Your Keys

```bash
age:fetch
```

This fetches your age keys from 1Password and caches them in `.keys/`.

### 3. Verify

```bash
age:check
```

Should output something like:

```
Checking age keys in: .keys
✓ Found 1 age key(s)

Public keys:
  dev: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

## Usage

### Working with Secrets

Once your keys are set up, use SOPS normally:

```bash
# Create/edit a secret
sops .stack/secrets/dev/web.sops.yaml

# View a secret
sops decrypt .stack/secrets/dev/web.sops.yaml

# Use stackpanel secrets commands
secrets:set API_KEY myvalue --group dev
secrets:get API_KEY --group dev
secrets:list --group dev
```

### Helper Commands

```bash
# Fetch keys (if missing or expired)
age:fetch

# Check key status
age:check

# View environment
echo $SOPS_AGE_KEY_CMD
echo $SOPS_KEYS_DIR
```

## Common Scenarios

### "I just joined the team"

```bash
# 1. Clone the repo
git clone https://github.com/your-org/your-project

# 2. Enter dev shell
cd your-project
nix develop

# 3. Sign in to 1Password
op signin

# 4. Fetch keys
age:fetch

# 5. You're ready!
sops .stack/secrets/dev/web.sops.yaml
```

### "Keys aren't working"

```bash
# Check status
age:check

# If no keys found, fetch them
age:fetch

# If still not working, check 1Password auth
op signin
age:fetch

# Verify environment
echo $SOPS_AGE_KEY_CMD
$SOPS_AGE_KEY_CMD  # Should output your private key
```

### "I need production keys"

```bash
# Set environment (if configured)
export STACKPANEL_ENV=prod

# Fetch production keys
age:fetch

# Or use environment variable override
OP_ITEM="op://production/sops-prod" age:fetch
```

### "Starting a new environment"

```bash
# Add the group name in config, then re-enter the devshell
nix develop --impure

# .stack/secrets/.sops.yaml is regenerated from the current recipients
```

## Directory Structure

After running `age:fetch`, you'll have:

```
.keys/
└── local.age        # Local private key material (never commit!)
```

The `.keys/` directory is automatically added to `.gitignore`.

## Environment Variables

Override default behavior:

```bash
# Use different keys directory
export SOPS_KEYS_DIR=.secrets/keys

# Use different 1Password item
export OP_ITEM="op://my-vault/my-item"
export OP_ACCOUNT="my-account"

# Different key name
export AGE_KEY_NAME="staging"
```

## Troubleshooting

### "age:fetch command not found"

Make sure you're in the dev shell:

```bash
nix develop
```

### "1Password CLI not found"

Install 1Password CLI:

```bash
# macOS
brew install 1password-cli

# Or use Nix (already in devShell if configured)
```

### "Permission denied on .keys/"

Fix permissions:

```bash
chmod 700 .keys
chmod 600 .keys/*.age
```

### "Failed to fetch from 1Password"

1. Check you're signed in: `op signin`
2. Verify item exists: `op item get "sops-dev"`
3. Check account: `op account list`

### "SOPS can't decrypt"

Verify your key is being used:

```bash
# Should output your private key
$SOPS_AGE_KEY_CMD

# If empty, fetch keys again
age:fetch
```

## What's Different from the Old Way?

If you're familiar with the old `age-key-cmd.sh` script:

**Old way:**
```bash
# Had to run shell script directly
./nix/stackpanel/secrets/lib/age-key-cmd.sh

# Had to manually set environment
export SOPS_AGE_KEY_CMD="$(pwd)/nix/stackpanel/secrets/lib/age-key-cmd.sh"

# Keys stored relative to script
```

**New way:**
```bash
# Commands available in PATH
age:fetch
age:check

# Environment auto-configured
# Just enter the dev shell and go

# Keys stored in project root .keys/
```

## Next Steps

- Read [README.md](./README.md) for detailed documentation
- See [INTEGRATION.md](./INTEGRATION.md) for integration patterns
- Check [CHANGELOG.md](./CHANGELOG.md) for what's new

## Getting Help

If you run into issues:

1. Check `age:check` output
2. Verify 1Password authentication
3. Review environment variables
4. See [README.md](./README.md) troubleshooting section
5. Ask your team lead or check internal docs

## Reference

### Configuration (Module)

```nix
stackpanel.secrets.age-key-cmd = {
  enable = true;                    # Enable age key tools
  keysDir = ".keys";                # Where to cache keys
  autoSetup = true;                 # Auto-configure environment
  onePassword = {
    enable = true;                  # Use 1Password
    account = "voytravel";          # Your OP account
    item = "op://vault/item";       # OP item reference
  };
};
```

### Available Commands

- `age:fetch` - Fetch keys from 1Password
- `age:check` - Verify keys are available
- `fetch-age-key` - Direct fetch command
- `read-age-keys` - Read cached keys
- `age-key-cmd` - Main key command (used by SOPS)
- `check-age-keys` - Direct check command

### Key Environment Variables

- `SOPS_AGE_KEY_CMD` - Command SOPS uses to get keys (auto-set)
- `SOPS_KEYS_DIR` - Directory for cached keys
- `OP_ACCOUNT` - 1Password account override
- `OP_ITEM` - 1Password item override
- `AGE_KEY_NAME` - Name for key files (default: "dev")

---

**Happy secret managing! 🔐**
