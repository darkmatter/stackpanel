# Stackpanel Go

Unified Go application containing the Stackpanel CLI and local agent.

## Overview

This package combines:
- **CLI** - Command-line interface for managing Stackpanel projects
- **Agent** - Local HTTP server for web UI integration
- **Shared packages** - Common utilities (envvars, exec, nix, etc.)

## Installation

```bash
# Build from source
go build -o stackpanel .

# Or install directly
go install github.com/darkmatter/stackpanel@latest
```

## Usage

### Interactive TUI

```bash
# Launch the interactive TUI
stackpanel
```

### Agent Server

```bash
# Start the agent (auto-detects project from current directory)
stackpanel agent

# With debug logging
stackpanel agent --debug

# On a specific port
stackpanel agent --port 9877

# With explicit project root
stackpanel agent --project-root /path/to/project
```

### Other Commands

```bash
# Show services status
stackpanel status

# Manage services
stackpanel services list
stackpanel services start <name>
stackpanel services stop <name>

# Manage users
stackpanel users list
stackpanel users add <github-username>

# Show environment variables
stackpanel env
```

## Project Structure

```
apps/stackpanel-go/
├── main.go              # Entry point
├── cmd/cli/             # CLI commands (cobra)
│   ├── root.go          # Root command with TUI
│   ├── agent.go         # Agent server command
│   ├── services.go      # Services management
│   ├── status.go        # Status display
│   └── ...
├── internal/            # Internal packages
│   ├── agent/           # Agent server internals
│   │   ├── config/      # Agent configuration
│   │   ├── project/     # Project detection/validation
│   │   └── server/      # HTTP server handlers
│   ├── tui/             # Terminal UI components
│   ├── nixconfig/       # Nix configuration helpers
│   └── ...
└── pkg/                 # Shared packages (can be imported)
    ├── common/          # Common utilities
    ├── envvars/         # Environment variable definitions
    ├── exec/            # Command execution
    ├── nix/             # Nix serialization
    ├── nixeval/         # Nix evaluation helpers
    └── services/        # Service management
```

## Agent API

The agent exposes a local HTTP API on `127.0.0.1:9876` (by default).

### Public Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/status` | GET | Detailed status |
| `/api/project/list` | GET | List known projects |
| `/api/project/current` | GET | Get current project |

### Protected Endpoints (require pairing)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/project/open` | POST | Open a project |
| `/api/project/close` | POST | Close current project |
| `/api/exec` | POST | Execute command |
| `/api/nix/eval` | POST | Evaluate Nix expression |
| `/api/files` | GET/POST | Read/write files |

## Development

```bash
# Run with hot reload
bun run dev

# Build
bun run build

# Test
bun run test

# Lint
bun run lint

# Format
bun run fmt
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `STACKPANEL_PROJECT_ROOT` | Override project root |
| `STACKPANEL_NIX_CONFIG` | Path to config.nix |
| `STACKPANEL_DATA_DIR` | Agent state directory |
| `STACKPANEL_AUTH_TOKEN` | Authentication token |

## Project Detection

The agent automatically detects Stackpanel projects by looking for:

1. `STACKPANEL_PROJECT_ROOT` environment variable
2. `.stackpanel/config.nix` in current directory
3. `.stackpanel/config.nix` in parent directories
4. Previously saved project from `~/.stackpanel/agent-state.json`
