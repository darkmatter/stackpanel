# Stackpanel Templates

Project templates for bootstrapping new stackpanel projects.

## Available Templates

| Template | Description | Use Case |
|----------|-------------|----------|
| `default` | devenv + flake-parts | Full-featured, recommended for most projects |
| `native` | Native Nix shell + flake-parts | When you want stackpanel without devenv |
| `devenv` | Standalone devenv.yaml | For devenv-first workflows (no flake.nix) |
| `minimal` | devenv without flake-parts | Simple flake without flake-parts |

## Quick Start

```bash
# Create a new directory
mkdir myproject && cd myproject

# Initialize from template (choose one)
nix flake init -t github:darkmatter/stackpanel          # default
nix flake init -t github:darkmatter/stackpanel#native   # native
nix flake init -t github:darkmatter/stackpanel#devenv   # devenv
nix flake init -t github:darkmatter/stackpanel#minimal  # minimal

# Enter the dev environment
direnv allow  # or: nix develop --impure
```

## Template Details

### default (Recommended)

Full-featured setup with devenv and flake-parts integration.

```bash
nix flake init -t github:darkmatter/stackpanel
```

**Structure:**
```
.
├── flake.nix              # Flake entry with flake-parts
├── nix/
│   └── devenv.nix         # Devenv options (packages, languages, etc.)
├── .stackpanel/
│   └── config.nix         # Stackpanel options
└── .envrc                 # Direnv configuration
```

**Features:**
- Multi-platform support (Linux/Darwin, x86_64/aarch64)
- All devenv features (processes, services, languages)
- All stackpanel features (CLI, IDE, theme, services)
- Clean separation of concerns

---

### native

Lightweight setup using native `mkShell` instead of devenv.

```bash
nix flake init -t github:darkmatter/stackpanel#native
```

**Structure:**
```
.
├── flake.nix              # Flake with flakeModules.native
├── .stackpanel/
│   └── config.nix         # Stackpanel options
└── .envrc                 # Direnv configuration
```

**Features:**
- Faster evaluation (no devenv dependency)
- Pure Nix implementation
- All stackpanel features
- No `devenv up` (use external process managers)

---

### devenv

Standalone devenv setup without a flake.nix.

```bash
nix flake init -t github:darkmatter/stackpanel#devenv
```

**Structure:**
```
.
├── devenv.yaml            # Devenv inputs and imports
├── devenv.nix             # Devenv + stackpanel options
├── .stackpanel/
│   └── config.nix         # Stackpanel options
└── .envrc                 # Direnv configuration
```

**Usage:**
```bash
devenv shell   # Enter the environment
devenv up      # Start processes
```

---

### minimal

Traditional flake.nix without flake-parts.

```bash
nix flake init -t github:darkmatter/stackpanel#minimal
```

**Structure:**
```
.
├── flake.nix              # Standard Nix flake
├── .stackpanel/
│   └── config.nix         # Stackpanel options
└── .envrc                 # Direnv configuration
```

**Features:**
- Simple, no abstraction layers
- Standard `forAllSystems` pattern
- Full control over flake outputs

## Configuration

All templates use the same `.stackpanel/config.nix` structure:

```nix
{
  enable = true;
  cli.enable = true;             # CLI tools
  theme.enable = true;           # Starship prompt
  ide.vscode.enable = true;      # VS Code integration

  # motd.enable = true;
  # aws.roles-anywhere.enable = true;
  # globalServices.postgres.enable = true;
}
```

## Learn More

- [Stackpanel Documentation](https://stackpanel.dev/docs)
- [Devenv Documentation](https://devenv.sh)
- [Flake Parts](https://flake.parts)
