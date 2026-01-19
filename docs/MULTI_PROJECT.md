# Multi-Project Support

Stackpanel supports managing multiple projects from a single agent instance. This allows you to develop multiple Stackpanel-enabled projects while keeping a single agent running.

## Overview

Projects are stored in `~/.config/stackpanel/stackpanel.yaml` and each project gets a unique ID (8-character hash of the path). The agent can serve requests for any registered project based on:

1. `X-Stackpanel-Project` HTTP header
2. `project` query parameter
3. Default project setting
4. Current project (legacy fallback)

## Project Identification

Each project has a unique ID derived from its path:

```bash
# View all projects with their IDs
stackpanel project list
```

Output:
```
Projects

  stackpanel [9b89a0a6] (current, default)
    Path: /Users/you/projects/stackpanel
    Last opened: just now

  my-app [a1b2c3d4]
    Path: /Users/you/projects/my-app
    Last opened: 2 hours ago
```

You can reference a project by:
- **ID**: `9b89a0a6`
- **Name**: `stackpanel`
- **Path**: `/Users/you/projects/stackpanel` or `~/projects/stackpanel`

## CLI Commands

### List Projects

```bash
stackpanel project list
```

### Add a Project

```bash
# Add current directory
stackpanel project add

# Add specific path
stackpanel project add ~/projects/my-app
```

### Show Project Info

```bash
# Show current project
stackpanel project info

# Show specific project
stackpanel project info my-app
stackpanel project info 9b89a0a6
```

### Set Default Project

The default project is used when no project is specified in API requests:

```bash
# Set default
stackpanel project default ~/projects/my-app

# Set current directory as default
stackpanel project default .

# Show current default
stackpanel project default

# Clear default
stackpanel project default --clear
```

### Remove a Project

```bash
# Remove by name, ID, or path
stackpanel project remove my-app
```

## API Usage

### Using HTTP Header (Recommended)

```bash
# Using project ID
curl -H "X-Stackpanel-Project: a1b2c3d4" \
     http://localhost:9876/api/nix/config

# Using project name
curl -H "X-Stackpanel-Project: my-app" \
     http://localhost:9876/api/nix/config
```

### Using Query Parameter

```bash
# Using project ID
curl "http://localhost:9876/api/nix/config?project=a1b2c3d4"

# Using project name
curl "http://localhost:9876/api/nix/config?project=my-app"
```

### Project Resolution Order

When a request comes in, the agent resolves the project in this order:

1. **X-Stackpanel-Project header** - If provided, uses this project
2. **project query parameter** - If header not present, checks query param
3. **Default project** - If neither specified, uses the default project
4. **Current project** - Legacy fallback to the "current" project

### No Project Error

If no project can be resolved, you'll get:

```json
{
  "error": "no_project",
  "message": "No project specified. Use X-Stackpanel-Project header, 'project' query parameter, or set a default project.",
  "hint": "GET /api/project/list to see available projects"
}
```

## TypeScript/JavaScript Usage

When using the agent client from the web UI or other TypeScript code:

```typescript
// Set project for all requests
const client = new AgentClient({
  baseUrl: "http://localhost:9876",
  projectId: "a1b2c3d4", // or project name
});

// Or set per-request
const response = await fetch("/api/nix/config", {
  headers: {
    "X-Stackpanel-Project": "my-app",
    "Authorization": `Bearer ${token}`,
  },
});
```

## Configuration File

Projects are stored in `~/.config/stackpanel/stackpanel.yaml`:

```yaml
current_project: /Users/you/projects/stackpanel
default_project: /Users/you/projects/my-app
projects:
  - id: 9b89a0a6
    path: /Users/you/projects/stackpanel
    name: stackpanel
    last_opened: 2024-01-15T10:30:00-08:00
  - id: a1b2c3d4
    path: /Users/you/projects/my-app
    name: my-app
    last_opened: 2024-01-15T08:15:00-08:00
version: 1
```

## Workflow Example

### Setting Up Multiple Projects

```bash
# Start in your first project
cd ~/projects/project-a
stackpanel project add
stackpanel project default .

# Add another project
stackpanel project add ~/projects/project-b

# List all projects
stackpanel project list
```

### Running the Agent

The agent can now be started from anywhere:

```bash
# Start agent (doesn't need to be in a project directory)
stackpanel agent

# Or start from any project directory (auto-registers it)
cd ~/projects/project-c
stackpanel agent
```

### Making Requests

```bash
# Request to project-a (the default)
curl http://localhost:9876/api/nix/config

# Request to project-b explicitly
curl -H "X-Stackpanel-Project: project-b" \
     http://localhost:9876/api/nix/config
```

## Environment Variables

- `STACKPANEL_USER_CONFIG`: Override the config file location (default: `~/.config/stackpanel/stackpanel.yaml`)

## Troubleshooting

### Project Not Found

If you get "project not found" errors:

1. Check the project is registered: `stackpanel project list`
2. Verify the ID/name is correct: `stackpanel project info <id>`
3. Add the project if missing: `stackpanel project add <path>`

### Project Invalid

If a project becomes invalid (moved or deleted):

```bash
# Check project status
stackpanel project info my-app

# Remove invalid project
stackpanel project remove my-app

# Re-add at new location
stackpanel project add ~/new/location/my-app
```

### Switching Default Project

```bash
# See current default
stackpanel project default

# Change to different project
stackpanel project default ~/projects/other-project
```
