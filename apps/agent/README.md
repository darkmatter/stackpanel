# StackPanel Agent

Local agent that runs on the developer's machine, enabling the StackPanel web UI to:

- Execute commands (nix run, git, etc.)
- Read/write project files
- Evaluate Nix expressions
- Generate files from Nix config

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
# Start agent in current project
stackpanel agent

# On a specific port
stackpanel agent --port 9877

# With debug logging
stackpanel agent --debug
```

Alternatively, run the agent binary directly:

```bash
# Start agent directly

## Configuration

Create `.stackpanel/agent.yaml` or `~/.config/stackpanel/agent.yaml`:

```yaml
project_root: "."
port: 9876
api_endpoint: "https://stackpanel.dev/api/agent"
allowed_commands:
  - nix
  - git
```

Environment variables:

- `STACKPANEL_PROJECT_ROOT` - Override project root
- `STACKPANEL_AUTH_TOKEN` - Authentication token
- `STACKPANEL_API_ENDPOINT` - API endpoint

## API

### HTTP Endpoints

| Endpoint | Method | Description |
| ------------------- | -------- | ----------------------- |
| `/health` | GET | Health check |
| `/api/exec` | POST | Execute command |
| `/api/nix/eval` | POST | Evaluate Nix expression |
| `/api/nix/generate` | POST | Run nix generate |
| `/api/files` | GET/POST | Read/write files |

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
    "path": ".stackpanel/team.nix"
  }
}
```

#### `file.write` - Write file

```json
{
  "type": "file.write",
  "payload": {
    "path": ".stackpanel/team.nix",
    "content": "{ users = { ... }; }"
  }
}
```

## Security

- Agent only listens on `127.0.0.1` by default
- File operations restricted to project root
- Optional command allowlist
- Authentication via token (for cloud sync)

## Development

```bash
# Run with hot reload
go run . --debug

# Build
go build -o stackpanel-agent .

# Test
go test ./...
```
