# Integration Guide: Age Key Tools in Secrets Module

This guide shows how to integrate the new derivation-based age key tools into your Stack secrets configuration.

## Quick Start

### Option 1: Using the Module (Recommended)

Add to your Stack configuration:

```nix
{
  imports = [
    ./nix/stack/secrets/lib/age-key-cmd.nix
  ];

  stack.secrets.age-key-cmd = {
    enable = true;
    keysDir = ".keys";
    onePassword = {
      enable = true;
      account = "voytravel";
      item = "op://voy-508-shared/sops-dev";
    };
    autoSetup = true;
  };
}
```

That's it! The module will:
- Add age key tools to your devShell
- Set `SOPS_AGE_KEY_CMD` automatically
- Add `.keys/` to `.gitignore`
- Provide `age:fetch` and `age:check` commands

### Option 2: Direct Integration in secrets/default.nix

If you want to integrate directly into the secrets module without using the separate module:

```nix
# In nix/stack/secrets/default.nix

let
  # ... existing lets ...

  # Add age key tools
  ageKeyTools = pkgs.callPackage ./lib/age-key-tools.nix {
    keysDir = ".keys";
    opAccount = "voytravel";
    opItem = "op://voy-508-shared/sops-dev";
  };

in {
  # ... existing config ...

  config = {
    stack.devshell.packages = [
      # ... existing packages ...
      ageKeyTools.fetchAgeKey
      ageKeyTools.ageKeyCmd
      ageKeyTools.checkAgeKeys
    ];

    stack.devshell.env = {
      # ... existing env vars ...
      SOPS_AGE_KEY_CMD = "${ageKeyTools.ageKeyCmd}/bin/age-key-cmd";
    };

    stack.scripts = {
      # ... existing scripts ...
      
      "age:fetch" = {
        exec = "${ageKeyTools.fetchAgeKey}/bin/fetch-age-key";
        description = "Fetch age keys from 1Password and cache locally";
      };

      "age:check" = {
        exec = "${ageKeyTools.checkAgeKeys}/bin/check-age-keys";
        description = "Check if age keys are available";
      };
    };

    stack.files.entries.".gitignore".lines = [
      # ... existing lines ...
      "# Age keys (managed by stack)"
      "/.keys/"
    ];
  };
}
```

## Advanced Integration

### Custom Key Sources

If you need to support multiple key sources (1Password, AWS Secrets Manager, etc.):

```nix
let
  # Build tools for different environments
  devAgeTools = pkgs.callPackage ./lib/age-key-tools.nix {
    keysDir = ".keys/dev";
    opAccount = "voytravel";
    opItem = "op://voy-508-shared/sops-dev";
  };

  prodAgeTools = pkgs.callPackage ./lib/age-key-tools.nix {
    keysDir = ".keys/prod";
    opAccount = "production-account";
    opItem = "op://production-vault/sops-prod";
  };

in {
  stack.scripts = {
    "age:fetch:dev" = {
      exec = "${devAgeTools.fetchAgeKey}/bin/fetch-age-key";
      description = "Fetch development age keys";
    };

    "age:fetch:prod" = {
      exec = "${prodAgeTools.fetchAgeKey}/bin/fetch-age-key";
      description = "Fetch production age keys";
    };
  };
}
```

### Using with Existing sops-age-keys

The new tools can work alongside your existing `sops-age-keys` script. The `ageKeyCmd` output is compatible with `SOPS_AGE_KEY_CMD`:

```nix
let
  ageKeyTools = pkgs.callPackage ./lib/age-key-tools.nix { };

  # Enhanced sops-age-keys that includes both local and fetched keys
  sops-age-keys = pkgs.writeShellApplication {
    name = "sops-age-keys";
    runtimeInputs = [ pkgs.sops ];
    text = ''
      # Step 1: Local AGE key (existing logic)
      LOCAL_KEY_FILE=.stack/keys/local.txt
      if [[ -f "$LOCAL_KEY_FILE" ]]; then
        LOCAL_KEY=$(grep "^AGE-SECRET-KEY-" "$LOCAL_KEY_FILE" 2>/dev/null || true)
        if [[ -n "$LOCAL_KEY" ]]; then
          echo "$LOCAL_KEY"
        fi
      fi

      # Step 2: Fetched keys from 1Password (new)
      if command -v ${ageKeyTools.readAgeKeys}/bin/read-age-keys &>/dev/null; then
        ${ageKeyTools.readAgeKeys}/bin/read-age-keys 2>/dev/null || true
      fi

      # Step 3: The generated .stack/secrets/.sops.yaml drives recipient selection
    '';
  };

in {
  config = {
    stack.devshell.env = {
      SOPS_AGE_KEY_CMD = "${sops-age-keys}/bin/sops-age-keys";
    };
  };
}
```

### Environment-Specific Configuration

Use Nix configuration to support different environments:

```nix
let
  environment = builtins.getEnv "STACKPANEL_ENV" or "dev";
  
  ageConfig = {
    dev = {
      keysDir = ".keys/dev";
      opItem = "op://voy-508-shared/sops-dev";
    };
    staging = {
      keysDir = ".keys/staging";
      opItem = "op://voy-508-shared/sops-staging";
    };
    prod = {
      keysDir = ".keys/prod";
      opItem = "op://production/sops-prod";
    };
  };

  ageKeyTools = pkgs.callPackage ./lib/age-key-tools.nix (ageConfig.${environment} // {
    opAccount = "voytravel";
  });

in {
  stack.devshell.env = {
    SOPS_AGE_KEY_CMD = "${ageKeyTools.ageKeyCmd}/bin/age-key-cmd";
    SOPS_KEYS_DIR = ageConfig.${environment}.keysDir;
  };
}
```

## Testing Your Integration

### 1. Verify Tools Are Available

```bash
# Enter your devShell
nix develop

# Check that tools are in PATH
which age-key-cmd
which fetch-age-key
which check-age-keys

# Verify environment variable
echo $SOPS_AGE_KEY_CMD
```

### 2. Test Key Fetching

```bash
# Fetch keys from 1Password
age:fetch
# or
fetch-age-key

# Check what keys were fetched
age:check
# or
check-age-keys
```

### 3. Test SOPS Integration

```bash
# Create a test secret file
echo "test: secret_value" | sops encrypt /dev/stdin > test.sops.yaml

# Try to decrypt it
sops decrypt test.sops.yaml

# Should output: test: secret_value
```

### 4. Test Key Command Directly

```bash
# The key command should output your private keys
$SOPS_AGE_KEY_CMD

# Should output lines starting with: AGE-SECRET-KEY-1...
```

## Troubleshooting Integration

### Issue: `age-key-cmd` not found

**Solution**: Ensure the module is imported or the tools are added to devShell packages:

```nix
stack.devshell.packages = [ ageKeyTools.ageKeyCmd ];
```

### Issue: `SOPS_AGE_KEY_CMD` not set

**Solution**: Either enable auto-setup in the module:

```nix
stack.secrets.age-key-cmd.autoSetup = true;
```

Or manually set it:

```nix
stack.devshell.env.SOPS_AGE_KEY_CMD = "${ageKeyTools.ageKeyCmd}/bin/age-key-cmd";
```

### Issue: Keys are fetched every time

**Solution**: The keys should be cached in `.keys/` directory. Check:

```bash
ls -la .keys/
# Should show *.age and *.age.pub files

# Check permissions
ls -l .keys/
# Private keys should be 600 (rw-------)
```

### Issue: Multiple key sources conflict

**Solution**: Use separate key directories or namespace your keys:

```nix
devTools = pkgs.callPackage ./lib/age-key-tools.nix {
  keysDir = ".keys/dev";
};

prodTools = pkgs.callPackage ./lib/age-key-tools.nix {
  keysDir = ".keys/prod";
};
```

## Migration Checklist

If migrating from the old `age-key-cmd.sh`:

- [ ] Import `age-key-cmd.nix` module or integrate tools directly
- [ ] Configure 1Password settings (account, item reference)
- [ ] Remove any manual SOPS_AGE_KEY_CMD exports from shell scripts
- [ ] Ensure `.keys/` is in `.gitignore`
- [ ] Test key fetching: `age:fetch`
- [ ] Test key availability: `age:check`
- [ ] Test SOPS operations: `sops .stack/secrets/dev/web.sops.yaml`
- [ ] Remove references to old `age-key-cmd.sh` script
- [ ] Update team documentation with new commands

## Best Practices

1. **Use the module when possible**: It handles all the boilerplate
2. **Keep keys in .gitignore**: Never commit `.keys/` directory
3. **Use environment-specific key directories**: Separate dev/staging/prod keys
4. **Document your 1Password structure**: Make it clear where keys are stored
5. **Test in CI**: Ensure key fetching works in automated environments
6. **Rotate keys regularly**: Use separate items for different rotation schedules

## Examples from Real Projects

### Example 1: Simple Project

```nix
# flake.nix or module config
{
  imports = [ ./nix/stack/secrets/lib/age-key-cmd.nix ];
  
  stack.secrets.age-key-cmd.enable = true;
  # Uses all defaults - perfect for single-environment projects
}
```

### Example 2: Multi-Environment Project

```nix
{
  imports = [ ./nix/stack/secrets/lib/age-key-cmd.nix ];
  
  stack.secrets.age-key-cmd = {
    enable = true;
    keysDir = ".secrets/keys/${environment}";
    onePassword = {
      account = if environment == "prod" then "production" else "development";
      item = "op://vault/sops-${environment}";
    };
  };
}
```

### Example 3: Custom Integration

```nix
let
  # Build multiple tool instances
  tools = lib.mapAttrs (env: cfg: 
    pkgs.callPackage ./lib/age-key-tools.nix cfg
  ) {
    dev = { keysDir = ".keys/dev"; opItem = "op://shared/dev"; };
    prod = { keysDir = ".keys/prod"; opItem = "op://prod/prod"; };
  };
in {
  stack.scripts = lib.mapAttrs' (env: tools:
    lib.nameValuePair "age:fetch:${env}" {
      exec = "${tools.fetchAgeKey}/bin/fetch-age-key";
      description = "Fetch ${env} age keys";
    }
  ) tools;
}
```

## See Also

- [README.md](./README.md) - Complete age key tools documentation
- [age-key-tools.nix](./age-key-tools.nix) - Core derivations
- [age-key-cmd.nix](./age-key-cmd.nix) - Module interface
- [../README.md](../README.md) - Main secrets documentation
