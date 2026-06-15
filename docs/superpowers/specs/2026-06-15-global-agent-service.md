# Global Stackpanel Agent Service

Related bead: `stackpanel-f1n`

## Problem

`stack agent` is currently optimized for being launched from inside a project directory or with `STACKPANEL_PROJECT_ROOT` set. That works for interactive development, but it is not ideal for the Studio UI or long-running local automation because the agent is tied to whichever shell started it.

We need a `stack agent service` workflow that installs a user-level login service and keeps one global Stackpanel agent running per user account.

## Goals

- Add `stack agent service` commands to install and manage a login-started user service.
- Support macOS `launchd` LaunchAgents and Linux `systemd --user` services.
- Run the installed agent globally per user, not per project.
- Use the user's home directory as the service working directory.
- Reuse the existing user-level project registry at `~/.config/stackpanel/stackpanel.yaml`.
- Make duplicate `stack agent` invocations detect and report the already-running agent instead of failing with `address already in use`.
- Make pairing survive normal service restarts.
- Keep the implementation compatible with Nix-managed installs and avoid GC-prone executable paths where possible.

## Non-Goals

- Running one OS service per project.
- Crawling the entire filesystem for Stackpanel projects by default.
- Replacing the existing project registry or project open/switch endpoints.
- Changing the agent's default HTTP API shape beyond what is needed for service lifecycle and single-instance behavior.
- Requiring `--impure` Nix evaluation or shell-specific environment assumptions.

## Current Codebase State

The current code already has several pieces needed for a global agent:

- `cmd/cli/agent.go` defines `stack agent` and supports `--project-root`, `--port`, `--bind`, and remote/CORS options.
- `internal/agent/config/config.go` loads `STACKPANEL_PROJECT_ROOT`, `STACKPANEL_DATA_DIR`, `STACKPANEL_BIND_ADDRESS`, and pairing test configuration from environment variables.
- `internal/agent/server/server.go` can start without a project, auto-register a project from cwd, or restore a saved current project from the project manager.
- `pkg/userconfig/userconfig.go` stores global user config in `~/.config/stackpanel/stackpanel.yaml`, including `CurrentProject`, `DefaultProject`, and `Projects`.
- `internal/agent/project` wraps the user config and already supports project detection, opening, listing, validation, and auto-registration.

Important gaps:

- Normal pairing keys and agent IDs are generated randomly on every startup in `internal/agent/server/jwt.go`, so tokens are invalidated after restart.
- There is no apparent single-instance/runtime-state check before binding `127.0.0.1:9876`.
- A second `stack agent` invocation while the service is running likely fails with a bind error instead of acting as a status/client command.
- There is no service manager abstraction or CLI for launchd/systemd user service installation.

## Design Overview

Implement `stack agent service` as a global user service manager around the existing agent.

The installed service should run:

```text
stack agent
```

with:

```text
WorkingDirectory = $HOME
```

Project identity should come from the existing user config registry, not from the service cwd. Interactive Stackpanel commands can continue to auto-register or open projects when run inside a repo.

## CLI Surface

Add a service subcommand under the existing `agent` command:

```bash
stack agent service install
stack agent service uninstall
stack agent service start
stack agent service stop
stack agent service restart
stack agent service status
stack agent service logs
```

Recommended flags:

```bash
stack agent service install --force
stack agent service install --exec /path/to/stack
stack agent service install --port 9876
stack agent service install --remote
```

If project registry commands are not already exposed at the CLI layer, add:

```bash
stack agent project add [path]
stack agent project list
stack agent project remove <path-or-id>
stack agent project open <path-or-id>
```

These should be thin wrappers around the existing `internal/agent/project` / `pkg/userconfig` behavior.

## Service Working Directory

The service must be global, so it should not use the cwd where `install` was run.

Use:

- systemd: `WorkingDirectory=%h`
- launchd: `WorkingDirectory` set to the user's home directory

This prevents accidentally pinning the service to one repo and makes login startup deterministic.

Project-specific operations must use explicit project paths from the registry/current-project state rather than relying on process cwd.

## Linux: systemd --user

Install path:

```text
~/.config/systemd/user/stackpanel-agent.service
```

Service template:

```ini
[Unit]
Description=Stackpanel Agent
After=network.target

[Service]
Type=simple
ExecStart={{ .ExecPath }} agent
WorkingDirectory=%h
Restart=on-failure
RestartSec=3
Environment=STACKPANEL_DATA_DIR=%h/.stack

[Install]
WantedBy=default.target
```

Install flow:

```bash
mkdir -p ~/.config/systemd/user
write stackpanel-agent.service
systemctl --user daemon-reload
systemctl --user enable --now stackpanel-agent.service
```

Status/log commands:

```bash
systemctl --user status stackpanel-agent.service
journalctl --user -u stackpanel-agent.service
```

## macOS: launchd LaunchAgent

Install path:

```text
~/Library/LaunchAgents/io.stackpanel.agent.plist
```

Plist template:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.stackpanel.agent</string>

  <key>ProgramArguments</key>
  <array>
    <string>{{ .ExecPath }}</string>
    <string>agent</string>
  </array>

  <key>WorkingDirectory</key>
  <string>{{ .Home }}</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>{{ .Home }}/Library/Logs/stackpanel/agent.log</string>

  <key>StandardErrorPath</key>
  <string>{{ .Home }}/Library/Logs/stackpanel/agent.err.log</string>
</dict>
</plist>
```

Install flow:

```bash
mkdir -p ~/Library/LaunchAgents ~/Library/Logs/stackpanel
write io.stackpanel.agent.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.stackpanel.agent.plist
launchctl enable gui/$(id -u)/io.stackpanel.agent
launchctl kickstart -k gui/$(id -u)/io.stackpanel.agent
```

Prefer modern `bootstrap`/`bootout`/`kickstart` commands. Fall back to `load -w` / `unload -w` only if needed for older macOS versions.

## Executable Path Selection

Do not blindly use a resolved `/nix/store/.../bin/stack` path for the service file, because it can be garbage-collected after upgrades.

Recommended selection order:

1. Explicit `--exec` path, if provided.
2. `exec.LookPath("stack")`, preserving the stable path found in `PATH`.
3. `exec.LookPath("stackpanel")`, if that is an alias/binary name in supported installs.
4. `os.Executable()` as a fallback, with a warning if it resolves into `/nix/store`.

The install command should print the selected executable path and warn when it may be GC-prone.

## Single-Instance Behavior

There should be exactly one active agent per user account.

Add runtime state under an XDG-style user state directory, for example:

```text
~/.local/state/stackpanel/agent/runtime.json
~/.local/state/stackpanel/agent/agent.lock
```

Runtime info shape:

```json
{
  "pid": 12345,
  "endpoint": "http://127.0.0.1:9876",
  "managedBy": "systemd-user",
  "startedAt": "2026-06-15T18:00:00Z"
}
```

Startup behavior:

1. Try to acquire the user-level agent lock.
2. If acquired, write runtime info and start the server.
3. If not acquired, read runtime info and health-check the endpoint.
4. If healthy, print a concise already-running status and exit `0`.
5. If stale, clean up stale runtime state and retry startup.

This turns duplicate `stack agent` runs into a useful status path instead of a bind failure.

## Pairing Persistence

Today normal JWT signing keys and agent IDs are random per startup. That means pairing is lost on restart.

For a global service, persist the agent identity/signing material in user state/config with restrictive permissions, for example:

```text
~/.local/state/stackpanel/agent/identity.json
```

Permissions:

```text
0600 file
0700 directory
```

Possible shape:

```json
{
  "agentId": "...",
  "signingKey": "base64url-encoded-random-32-bytes",
  "createdAt": "2026-06-15T18:00:00Z"
}
```

`JWTManager` should load this identity in normal mode, creating it on first run if missing. Existing `STACKPANEL_TEST_PAIRING_TOKEN` deterministic behavior should remain for tests and CI.

## Pairing Command Behavior

Pairing commands should target the running global agent:

1. If an agent is already running, use its endpoint.
2. If the service is installed but stopped, start it and wait for `/health`.
3. If no service is installed, start a temporary foreground/background agent or instruct the user to install the service.

The Studio UI should only need to pair with the global per-user agent once, and that pairing should survive service restarts.

## Project Discovery

Use explicit registration, not filesystem crawling by default.

Existing behavior already supports the intended model:

- Running `stack agent` or other project-aware commands from inside a repo can auto-register/open the current project.
- Registered projects live in `~/.config/stackpanel/stackpanel.yaml`.
- A global service can restore the saved current project or allow the UI to select from known projects.

Future optional discovery can scan configured roots such as `~/git` or `~/work`, but it should be opt-in.

## Implementation Plan

1. Add a `daemon` or `service` package with a platform-specific interface:

   ```go
   type Manager interface {
     Install(opts InstallOptions) error
     Uninstall() error
     Start() error
     Stop() error
     Restart() error
     Status() (*Status, error)
     Logs(opts LogOptions) error
   }
   ```

2. Implement systemd user service rendering and lifecycle commands on Linux.
3. Implement launchd LaunchAgent rendering and lifecycle commands on macOS.
4. Add `stack agent service ...` Cobra commands under `cmd/cli/agent.go` or adjacent files.
5. Add executable path selection with tests.
6. Add runtime lock/state and duplicate-agent detection before `server.Start()`.
7. Persist normal-mode JWT identity/signing key and update `JWTManager` construction.
8. Ensure global service startup from `$HOME` restores existing current project via the project manager.
9. Add or expose project registry CLI commands if needed.
10. Add tests for service rendering, executable path selection, runtime state, and identity persistence.

## Acceptance Criteria

- `stack agent service install` installs and starts a global user agent on Linux via `systemd --user`.
- `stack agent service install` installs and starts a global user agent on macOS via launchd.
- The installed service uses the user's home directory as cwd.
- The global agent works when started outside a project directory.
- Registered projects from `~/.config/stackpanel/stackpanel.yaml` are visible/selectable.
- Running `stack agent` while the service is healthy exits `0` and prints the running endpoint/status.
- Pairing survives a normal service restart.
- Tests cover service file rendering, executable path selection, single-instance/runtime state, and persisted identity loading.

## Open Questions

- Should the binary name in docs and service files prefer `stack` or `stackpanel`, or support both equally?
- Should `stack agent service install` enable remote/Tailscale mode, or keep localhost-only by default and require an explicit flag?
- Should `stack agent` automatically start the installed service when invoked interactively and no agent is running?
- Where should status/log output be normalized so `service status` has a consistent shape across launchd and systemd?
