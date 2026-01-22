# Stackpanel Development Mode

When developing Stackpanel while also using it in other projects, you need the `stackpanel` CLI to point to your local development version. This document explains how to set that up.

> The `stackpanel dev ...` commands have been renamed to `stackpanel debug ...`. The old `dev` alias still works for compatibility.

## Quick Start

The fastest way to enable dev mode:

```bash
# Option 1: Environment variable (add to your shell profile)
export STACKPANEL_DEV_REPO=~/path/to/stackpanel

# Option 2: CLI config (persistent)
stackpanel debug enable ~/path/to/stackpanel
# (Legacy alias: stackpanel dev enable ...)
```

## How It Works

When dev mode is enabled, the CLI runs commands via `go run` from your local repository instead of using the installed binary:

```
stackpanel status
# Actually runs: go run ~/path/to/stackpanel/apps/stackpanel-go status
```

This means:
- Changes to Go code are picked up immediately (after the first compile)
- No need to rebuild or reinstall the binary
- You can develop Stackpanel while using it in real projects

## Setup Methods

### Method 1: Environment Variable (Recommended for Quick Testing)

Set `STACKPANEL_DEV_REPO` in your shell:

```bash
# In ~/.bashrc, ~/.zshrc, or equivalent
export STACKPANEL_DEV_REPO="$HOME/projects/stackpanel"
```

The environment variable takes precedence over config file settings.

### Method 2: CLI Config (Recommended for Persistent Use)

Use the built-in `debug` subcommand (alias: `dev`):

```bash
# Enable dev mode
stackpanel debug enable ~/projects/stackpanel
# Legacy alias:
# stackpanel dev enable ~/projects/stackpanel

# Check status
stackpanel debug status

# Disable dev mode
stackpanel debug disable
# Legacy alias: stackpanel dev disable
```

This stores the setting in `~/.config/stackpanel/stackpanel.yaml`:

```yaml
dev_mode:
  enabled: true
  repo_path: /Users/you/projects/stackpanel
```

### Method 3: Wrapper Script (Most Flexible)

For advanced use cases, install the wrapper script:

```bash
# Copy the wrapper to your PATH (before any installed stackpanel)
cp scripts/stackpanel-wrapper.sh ~/.local/bin/stackpanel
chmod +x ~/.local/bin/stackpanel

# Rename the original binary if needed
mv /usr/local/bin/stackpanel /usr/local/bin/stackpanel-bin
```

The wrapper script:
1. Checks `STACKPANEL_DEV_REPO` environment variable
2. Falls back to config file debug mode settings
3. Falls back to the installed binary (`stackpanel-bin`)

### Method 4: Shell Alias (Simplest)

Add an alias to your shell profile:

```bash
# In ~/.bashrc or ~/.zshrc
alias stackpanel='go run ~/projects/stackpanel/apps/stackpanel-go'
```

Simple but doesn't support easy toggling.

### Method 5: Direnv per-project (Project-Specific)

Use direnv to enable dev mode only in certain directories:

```bash
# In a project's .envrc
export STACKPANEL_DEV_REPO="$HOME/projects/stackpanel"
```

## Debugging

Enable debug output to see which binary is being used:

```bash
STACKPANEL_DEBUG=1 stackpanel status
# Output: [debug-mode] Running: go run /path/to/stackpanel/apps/stackpanel-go status
```

## Performance Considerations

Running via `go run` is slower than a compiled binary because:
1. Go needs to compile the code on first run
2. Subsequent runs use cached compilation but still have overhead

For quick commands, the difference is negligible (~500ms extra on first run).
For long-running commands like `stackpanel agent`, the startup cost is amortized.

## Switching Between Dev and Production

```bash
# Quick toggle via env var
export STACKPANEL_DEV_REPO=~/projects/stackpanel  # Debug mode
unset STACKPANEL_DEV_REPO                          # Production mode

# Or use the CLI
stackpanel debug enable ~/projects/stackpanel       # Debug mode
stackpanel debug disable                             # Production mode
# Legacy alias: stackpanel dev enable/disable

# Check current mode
stackpanel debug status
# Legacy alias: stackpanel dev status
```

## Troubleshooting

### "Could not find stackpanel binary"

Make sure:
1. The Go toolchain is installed and in your PATH
2. The repo path is correct: `ls ~/projects/stackpanel/apps/stackpanel-go/main.go`

### "Invalid stackpanel repository"

The dev enable command validates the path. Make sure:
- The path points to the root of the stackpanel repository
- The path contains `apps/stackpanel-go/main.go`

### Changes Not Being Picked Up

Go caches compiled packages. If your changes aren't being picked up:

```bash
# Clear Go build cache
go clean -cache

# Or force recompilation
go build -a ./apps/stackpanel-go/...
```

### Slow First Run

The first `go run` compiles the entire binary. Subsequent runs use cached compilation.
This is normal and expected.
