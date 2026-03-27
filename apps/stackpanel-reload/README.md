# stackpanel-reload

Background shell rebuild with PTY hot-swap for stackpanel.

When a watched config file changes, `stackpanel-reload` runs `nix develop
--impure` in the background. When it succeeds, it swaps the interactive PTY —
**your shell hooks re-run, the new environment becomes active, and your terminal
stays open the whole time.**

---

## Quickstart

### Via stackpanel (recommended)

Enable the module in `.stack/config.nix`:

```nix
stackpanel.devshell.reload.enable = true;
```

Re-enter the devshell (`nix develop --impure`), then use the registered command:

```
stackpanel shell
# or: x shell / sp shell
```

Your shell now auto-reloads whenever `flake.nix`, `flake.lock`, `.stack/`, or
`nix/` change.

### Standalone

```bash
# Default: wraps `nix develop --impure --command $SHELL`
stackpanel-reload

# Explicit command
stackpanel-reload -- nix develop --impure --command zsh
```

---

## What happens when a file changes

```
┌─────────────────────────────────────────────────────────┐
│ You edit flake.nix (or any watched file)                │
└─────────────────────┬───────────────────────────────────┘
                      │ debounce (500ms default)
                      ▼
          Background: nix develop --impure --command true
          (hooks run, derivation builds, stays silent)
                      │
           ┌──────────┴──────────┐
           │ success             │ failure
           ▼                     ▼
    PTY hot-swap:         Status line shows:
    ↻ shell reloaded      ✗ rebuild failed (exit N)
    New session starts    Old session keeps running
    (hooks re-ran!)       Ctrl+Alt+R to retry
```

The status line at the bottom of your terminal shows live progress — it never
interferes with your prompt because it writes to stderr using ANSI cursor
save/restore.

---

## Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+Alt+R` | Trigger a rebuild immediately (without editing a file) |
| `Ctrl+Alt+L` | Print the list of currently watched paths |

---

## CLI reference

```
stackpanel-reload [OPTIONS] [-- COMMAND...]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--root DIR` | `$PWD` | Project root (where watched paths are resolved from) |
| `--debounce MS` | `500` | Quiet period after last file change before rebuilding |
| `--watch PATH` | — | Extra paths to watch (repeatable; adds to the default set) |
| `--log FILE` | `$STACKPANEL_STATE_DIR/reload.log` | Write structured logs to a file |
| `-- COMMAND` | `nix develop --impure --command $SHELL` | Shell command to run in the PTY |

**Verbosity:** set `RUST_LOG=debug` for detailed logs.

---

## Nix module options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stackpanel.devshell.reload.enable` | bool | `false` | Enable the module |
| `stackpanel.devshell.reload.watchPaths` | `[str]` | standard set | Override watched paths |
| `stackpanel.devshell.reload.debounceMs` | int | `500` | Debounce delay |

The **standard watch set** is: `flake.nix`, `flake.lock`, `devenv.nix`,
`devenv.yaml`, `.stack/`, `nix/`.

To watch additional paths without replacing the defaults, use `--watch` at
runtime or add them in config:

```nix
stackpanel.devshell.reload.watchPaths = [
  "flake.nix"
  "flake.lock"
  ".stack"
  "nix"
  "some/custom/path"
];
```

---

## CI / non-TTY behaviour

When stdout is not a terminal (CI, scripts, `nix develop --command ...`),
`stackpanel-reload` falls back to executing the command directly with no PTY
machinery, file watching, or status line. Zero overhead in CI.

---

## Architecture notes

- **File watching** — `notify` crate, debounced in a background thread. Metadata-only changes (chmod, timestamp touches) are filtered out.
- **Background rebuild** — `nix develop --impure --command true` as a regular child process (no PTY). Silences output; only exit code matters.
- **PTY hot-swap** — generation-based event loop. When rebuild succeeds, a new `nix develop` PTY is spawned, the stdin writer is swapped, the new output forwarder starts, and the old PTY session is dropped (SIGHUP → old shell exits).
- **Status line** — DECSC/DECRC cursor save/restore writes to stderr independently of the shell's stdout.
