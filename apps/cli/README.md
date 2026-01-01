# Stackpanel CLI

A unified command-line interface for managing the Stackpanel development environment.
Built with [Bubble Tea](https://github.com/charmbracelet/bubbletea) for beautiful, interactive terminal UIs.

## Installation

The CLI is automatically built when you enter the devenv shell. It's placed in `$DEVENV_STATE/stackpanel` and added to your PATH.

### Manual Build

```bash
cd cli
make build      # Build for current platform
make install    # Install to $GOBIN
make release    # Build for all platforms
```

## Usage

```bash
stackpanel [command] [subcommand] [flags]
```

### Commands

#### Status Overview

```bash
stackpanel status           # Interactive status dashboard (auto-refreshing)
stackpanel status --static  # Static status output
```

The interactive dashboard shows:

- Live service status with auto-refresh every 2 seconds
- Service details (PID, port, project registrations)
- Caddy reverse proxy status
- Certificate status

Press `r` to refresh, `q` to quit.

#### Services Management

Manage global development services (PostgreSQL, Redis, Minio).

```bash
stackpanel services start           # Start all services (interactive TUI)
stackpanel services start postgres  # Start specific service
stackpanel services start pg redis  # Start multiple services
stackpanel services start --no-tui  # Non-interactive mode

stackpanel services stop            # Stop all services
stackpanel services status          # Show service status
stackpanel services restart         # Restart services
stackpanel services logs postgres   # View service logs
stackpanel services logs redis -f   # Follow logs
```

**Aliases**: `svc`, `s`

**Service aliases**:

- `postgres`, `pg`, `postgresql`
- `redis`, `rd`
- `minio`, `s3`

#### Caddy (Reverse Proxy)

Manage the global Caddy reverse proxy.

```bash
stackpanel caddy start              # Start or reload Caddy
stackpanel caddy stop               # Stop Caddy
stackpanel caddy status             # Show Caddy status
stackpanel caddy list               # List configured sites

stackpanel caddy add myapp.localhost localhost:3000
stackpanel caddy add api.localhost localhost:8080 --tls
stackpanel caddy remove myapp.localhost
```

## Global Flags

```bash
--verbose, -v    # Enable verbose output
--no-color       # Disable color output
--help, -h       # Show help
--version        # Show version
```

## Architecture

The CLI manages **project-local services** by default, with **global Caddy**:

1. **Services are project-local** - PostgreSQL, Redis, Minio run as separate instances per project
2. **Data is isolated** - Service data is stored in `.stackpanel/state/services/` within your project
3. **Different versions** - Each project can use different PostgreSQL versions, etc.
4. **Caddy is global** - Shared across projects to avoid port 443 conflicts
5. **Caddy symlinks** - Project sites are symlinked from `.stackpanel/caddy/` for easy access

### Directory Structure

```
# Project-local services (per project)
<project>/.stackpanel/
├── state/
│   └── services/
│       ├── postgres/
│       │   ├── data/           # PostgreSQL data directory
│       │   ├── socket/         # Unix socket
│       │   ├── postgres.pid    # PID file
│       │   └── postgres.log    # Log file
│       ├── redis/
│       │   ├── data/
│       │   ├── redis.pid
│       │   ├── redis.log
│       │   └── redis.conf
│       └── minio/
│           ├── data/
│           ├── minio.pid
│           └── minio.log
└── caddy/                      # Symlinks to global config
    └── myapp_localhost.caddy -> ~/.config/caddy/sites.d/myapp_localhost.caddy

# Global Caddy (shared across projects)
~/.config/caddy/
├── Caddyfile           # Auto-generated, imports sites.d/
├── caddy.pid
└── sites.d/            # Per-project site configs
    └── stackpanel_localhost.caddy
```

## Development

```bash
cd cli
make dev        # Hot reload development
make test       # Run tests
make lint       # Lint code
make fmt        # Format code
```

## Tech Stack

- **[Cobra](https://github.com/spf13/cobra)** - CLI framework
- **[Bubble Tea](https://github.com/charmbracelet/bubbletea)** - TUI framework (Elm architecture)
- **[Bubbles](https://github.com/charmbracelet/bubbles)** - TUI components (spinners, progress bars, tables)
- **[Lip Gloss](https://github.com/charmbracelet/lipgloss)** - Terminal styling

## Why Go?

- **Single binary** - No runtime dependencies, easy to distribute
- **Fast startup** - Important for CLI tools used frequently
- **Cross-platform** - Easy to build for macOS, Linux, Windows
- **Charm ecosystem** - Best-in-class TUI libraries
- **Cobra framework** - Industry-standard CLI library with great UX
