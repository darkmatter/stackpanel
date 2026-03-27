# Stack Development Mode

When developing Stack while also using it in other projects, you need the `stack` CLI to point to your local development version. This document explains how to set that up.

> The `stack dev ...` commands have been renamed to `stack debug ...`. The old `dev` alias still works for compatibility.

## Quick Start

The fastest way to enable dev mode:

```bash
# Option 1: Environment variable (add to your shell profile)
export STACKPANEL_DEV_REPO=~/path/to/stack

# Option 2: CLI config (persistent)
stack debug enable ~/path/to/stack
# (Legacy alias: stack dev enable ...)
```

## How It Works

When dev mode is enabled, the CLI runs commands via `go run` from your local repository instead of using the installed binary:

```
stack status
# Actually runs: go run ~/path/to/stack/apps/stack-go status
```

This means:
- Changes to Go code are picked up immediately (after the first compile)
- No need to rebuild or reinstall the binary
- You can develop Stack while using it in real projects

## Setup Methods

### Method 1: Environment Variable (Recommended for Quick Testing)

Set `STACKPANEL_DEV_REPO` in your shell:

```bash
# In ~/.bashrc, ~/.zshrc, or equivalent
export STACKPANEL_DEV_REPO="$HOME/projects/stack"
```

The environment variable takes precedence over config file settings.

### Method 2: CLI Config (Recommended for Persistent Use)

Use the built-in `debug` subcommand (alias: `dev`):

```bash
# Enable dev mode
stack debug enable ~/projects/stack
# Legacy alias:
# stack dev enable ~/projects/stack

# Check status
stack debug status

# Disable dev mode
stack debug disable
# Legacy alias: stack dev disable
```

This stores the setting in `~/.config/stack/stack.yaml`:

```yaml
dev_mode:
  enabled: true
  repo_path: /Users/you/projects/stack
```

### Method 3: Wrapper Script (Most Flexible)

For advanced use cases, install the wrapper script:

```bash
# Copy the wrapper to your PATH (before any installed stack)
cp scripts/stack-wrapper.sh ~/.local/bin/stack
chmod +x ~/.local/bin/stack

# Rename the original binary if needed
mv /usr/local/bin/stack /usr/local/bin/stack-bin
```

The wrapper script:
1. Checks `STACKPANEL_DEV_REPO` environment variable
2. Falls back to config file debug mode settings
3. Falls back to the installed binary (`stack-bin`)

### Method 4: Shell Alias (Simplest)

Add an alias to your shell profile:

```bash
# In ~/.bashrc or ~/.zshrc
alias stack='go run ~/projects/stack/apps/stack-go'
```

Simple but doesn't support easy toggling.

### Method 5: Direnv per-project (Project-Specific)

Use direnv to enable dev mode only in certain directories:

```bash
# In a project's .envrc
export STACKPANEL_DEV_REPO="$HOME/projects/stack"
```

## Debugging

Enable debug output to see which binary is being used:

```bash
STACKPANEL_DEBUG=1 stack status
# Output: [debug-mode] Running: go run /path/to/stack/apps/stack-go status
```

## Performance Considerations

Running via `go run` is slower than a compiled binary because:
1. Go needs to compile the code on first run
2. Subsequent runs use cached compilation but still have overhead

For quick commands, the difference is negligible (~500ms extra on first run).
For long-running commands like `stack agent`, the startup cost is amortized.

## Switching Between Dev and Production

```bash
# Quick toggle via env var
export STACKPANEL_DEV_REPO=~/projects/stack  # Debug mode
unset STACKPANEL_DEV_REPO                          # Production mode

# Or use the CLI
stack debug enable ~/projects/stack       # Debug mode
stack debug disable                             # Production mode
# Legacy alias: stack dev enable/disable

# Check current mode
stack debug status
# Legacy alias: stack dev status
```

## Troubleshooting

### "Could not find stack binary"

Make sure:
1. The Go toolchain is installed and in your PATH
2. The repo path is correct: `ls ~/projects/stack/apps/stack-go/main.go`

### "Invalid stack repository"

The dev enable command validates the path. Make sure:
- The path points to the root of the stack repository
- The path contains `apps/stack-go/main.go`

### Changes Not Being Picked Up

Go caches compiled packages. If your changes aren't being picked up:

```bash
# Clear Go build cache
go clean -cache

# Or force recompilation
go build -a ./apps/stack-go/...
```

### Slow First Run

The first `go run` compiles the entire binary. Subsequent runs use cached compilation.
This is normal and expected.
