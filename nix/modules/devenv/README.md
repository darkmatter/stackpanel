# devenv/

Development environment integration - wraps devenv as a stackpanel plugin.

## Files

| File | Purpose |
|------|---------|
| `theme.nix` | Shell prompt theming (starship) |
| `starship.toml` | Starship configuration |

## Planned Options

```nix
stackpanel.devenv = {
  enable = true;

  # Language support
  languages = {
    go.enable = true;
    javascript.enable = true;
    python.enable = true;
  };

  # Services
  services = {
    postgres.enable = true;
    redis.enable = true;
  };

  # Escape hatch
  extraConfig = { /* raw devenv config */ };
};
```

## TODO

- [ ] Create devenv wrapper module
- [ ] Language detection (auto-enable based on project files)
- [ ] Service presets (postgres, redis, etc.)
- [ ] Integrate secrets (auto-load decrypted secrets in devshell)
- [ ] VSCode integration (terminal profile, settings)
- [ ] Shell theming (starship presets)
