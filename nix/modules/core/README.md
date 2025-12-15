# core/

Base stackpanel functionality - options, file generation, and data directory management.

## Files

| File | Purpose |
|------|---------|
| `options.nix` | Base `stackpanel.*` options (currently empty, options in generate.nix) |
| `generate.nix` | File accumulator + `nix run .#generate` command |
| `datadir.nix` | `.stackpanel/` directory support |

## Key Concepts

### File Accumulator Pattern

All modules push files to `stackpanel.files`:

```nix
config.stackpanel.files.".github/workflows/ci.yml" = yamlContent;
config.stackpanel.files."Dockerfile" = dockerContent;
```

Then `nix run .#generate` writes them all to disk.

### Data Directory

Agent writes config to `.stackpanel/`:

- `.stackpanel/team.nix` - synced from GitHub
- `.stackpanel/config.nix` - project settings

User's `flake.nix` imports these files.

## TODO

- [ ] Consolidate options.nix into generate.nix (or vice versa)
- [ ] Add `nix run .#generate-clean` to remove managed files
- [ ] Add file checksums to detect manual edits
- [ ] Support merge strategies (append vs overwrite)
