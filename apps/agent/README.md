# StackPanel Agent

Local agent that runs on the developer's machine, enabling the StackPanel web UI to:

- Execute commands (nix run, git, etc.)
- Read/write project files
- Evaluate Nix expressions
- Generate files from Nix config
- Manage project selection and validation

## Installation

```bash
# Build from source
go build -o stackpanel-agent .

# Or install directly
go install github.com/darkmatter/stackpanel/agent@latest
```

## Usage

The recommended way to start the agent is via the StackPanel CLI:

```bash
# Start agent (will prompt to select a project if none saved)
stackpanel agent

# Start agent with a specific project
stackpanel agent --project /path/to/project

# On a specific port
stackpanel agent --port 9877

# With debug logging
stackpanel agent --debug
```

Alternatively, run the agent binary directly:

```bash
./stackpanel-agent --debug
```

## Project Management

The agent manages project selection and validation:

- **Project state is persisted** in `~/.stackpanel/agent-state.json`
- **Projects must be git repositories** (have a `.git` folder)
- **Projects must be valid Stackpanel projects** (have `config.stackpanel` in their flake or a `.stackpanel` directory)

When the agent starts:
1. It loads the last-used project from saved state
2. Validates the project still exists and is valid
3. If no valid project, the agent runs without a project (API calls requiring a project will return an error)

Use the project management API endpoints to select a project at runtime.

## Configuration

Create `.stackpanel/agent.yaml` or `~/.config/stackpanel/agent.yaml`:

```yaml
# Project root (optional - typically managed via project manager)
# project_root: "/path/to/your/project"

# Port for local HTTP server
port: 9876

# StackPanel API endpoint (for cloud sync)
api_endpoint: "https://stackpanel.dev/api/agent"

# Allowed commands (empty = all allowed)
allowed_commands:
  - nix
  - git

# Data directory for agent state
data_dir: ~/.stackpanel

# Allowed web UI origins for CORS
allowed_origins: []
```

### Environment Variables

- `STACKPANEL_PROJECT_ROOT` - Override project root (takes precedence over saved state)
- `STACKPANEL_AUTH_TOKEN` - Authentication token
- `STACKPANEL_API_ENDPOINT` - API endpoint

## API

### Project Management Endpoints

| Endpoint | Method | Description |
| ----------------------- | ------ | ------------------------------------------- |
| `/api/project/current` | GET | Get currently active project |
| `/api/project/list` | GET | List all known projects |
| `/api/project/open` | POST | Open/select a project (validates first) |
| `/api/project/close` | POST | Close the current project |
| `/api/project/validate` | POST | Validate a path without opening it |
| `/api/project/remove` | DELETE | Remove a project from the known list |

#### Open Project Request

```json
{
  "path": "/path/to/project"
}
```

#### Response (success)

```json
{
  "success": true,
  "data": {
    "project": {
      "path": "/path/to/project",
      "name": "project",
      "last_opened": "2024-01-15T10:30:00Z",
      "active": true
    }
  }
}
```

#### Response (validation error)

```json
{
  "success": true,
  "data": {
    "valid": false,
    "error": "not_git_repo",
    "message": "Directory is not a git repository (no .git folder found)"
  }
}
```

### Health/Status Endpoints

| Endpoint | Method | Description |
| --------- | ------ | ------------------------------------ |
| `/health` | GET | Health check (includes project info) |
| `/status` | GET | Detailed status |

### Project-Dependent Endpoints

These endpoints require a project to be open. Returns `412 Precondition Required` if no project is selected.

| Endpoint | Method | Description |
| ------------------- | -------- | ----------------------- |
| `/api/exec` | POST | Execute command |
| `/api/nix/eval` | POST | Evaluate Nix expression |
| `/api/nix/generate` | POST | Run nix generate |
| `/api/nix/data` | GET/POST | Read/write Nix data |
| `/api/nix/data/list`| GET | List data entities |
| `/api/files` | GET/POST | Read/write files |
| `/api/secrets/set` | POST | Set a secret |

### WebSocket (`/ws`)

Message format:

```json
{
  "id": "unique-id",
  "type": "exec|nix.eval|nix.generate|file.read|file.write",
  "payload": { ... }
}
```

Response format:

```json
{
  "id": "unique-id",
  "success": true,
  "data": { ... }
}
```

### Message Types

#### `exec` - Execute command

```json
{
  "type": "exec",
  "payload": {
    "command": "nix",
    "args": ["run", ".#generate"]
  }
}
```

#### `nix.eval` - Evaluate Nix expression

```json
{
  "type": "nix.eval",
  "payload": {
    "expression": "stackpanel.secrets.schema"
  }
}
```

#### `nix.generate` - Run generate

```json
{
  "type": "nix.generate",
  "payload": {}
}
```

#### `file.read` - Read file

```json
{
  "type": "file.read",
  "payload": {
    "path": ".stackpanel/data/users.nix"
  }
}
```

#### `file.write` - Write file

```json
{
  "type": "file.write",
  "payload": {
    "path": ".stackpanel/data/users.nix",
    "content": "{ ... }"
  }
}
```

## Security

- Agent only listens on `127.0.0.1` (loopback only)
- File operations restricted to project root
- Optional command allowlist
- Authentication via pairing token
- CORS protection with configurable origins

## Development

```bash
# Run with hot reload (via air)
bun run dev

# Build
go build -o stackpanel-agent .

# Test
go test ./...
```
