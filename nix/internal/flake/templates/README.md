# Stack Templates

Project templates for bootstrapping new Stack projects.

## Available Templates

| Template | Description | Use Case |
|----------|-------------|----------|
| `default` | devenv + flake-parts | Full-featured, recommended for most projects |
| `native` | Native Nix shell + flake-parts | When you want Stack without devenv |
| `devenv` | Standalone devenv.yaml | For devenv-first workflows (no flake.nix) |
| `minimal` | devenv without flake-parts | Simple flake without flake-parts |

## Quick Start

```bash
# Create a new directory
mkdir myproject && cd myproject

# Initialize from template (choose one)
nix flake init -t github:darkmatter/stack          # default
nix flake init -t github:darkmatter/stack#native   # native
nix flake init -t github:darkmatter/stack#devenv   # devenv
nix flake init -t github:darkmatter/stack#minimal  # minimal

# Enter the dev environment
direnv allow  # or: nix develop --impure
```

## Template Details

### default (Recommended)

Full-featured setup with devenv and flake-parts integration.

```bash
nix flake init -t github:darkmatter/stack
```

**Structure:**
```
.
├── flake.nix              # Flake entry with flake-parts
├── nix/
│   └── devenv.nix         # Devenv options (packages, languages, etc.)
├── .stack/
│   └── config.nix         # Stack options
└── .envrc                 # direnv configuration
```

**Features:**
- Multi-platform support (Linux/Darwin, x86_64/aarch64)
- All devenv features (processes, services, languages)
- All Stack features (CLI, IDE, theme, services)
- Clean separation of concerns

---

### native

Lightweight setup using native `mkShell` instead of devenv.

```bash
nix flake init -t github:darkmatter/stack#native
```

**Structure:**
```
.
├── flake.nix              # Flake with flakeModules.native
├── .stack/
│   └── config.nix         # Stack options
└── .envrc                 # direnv configuration
```

**Features:**
- Faster evaluation (no devenv dependency)
- Pure Nix implementation
- All Stack features
- No `devenv up` (use external process managers)

---

### devenv

Standalone devenv setup without a flake.nix.

```bash
nix flake init -t github:darkmatter/stack#devenv
```

**Structure:**
```
.
├── devenv.yaml            # Devenv inputs and imports
├── devenv.nix             # Devenv + Stack options
├── .stack/
│   └── config.nix         # Stack options
└── .envrc                 # direnv configuration
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
nix flake init -t github:darkmatter/stack#minimal
```

**Structure:**
```
.
├── flake.nix              # Standard Nix flake
├── .stack/
│   └── config.nix         # Stack options
└── .envrc                 # direnv configuration
```

**Features:**
- Simple, no abstraction layers
- Standard `forAllSystems` pattern
- Full control over flake outputs

## Configuration

All templates use the same `.stack/config.nix` structure:

```nix
{
  enable = true;
  
  # Shell prompt theme
  theme.enable = true;
  
  # VS Code integration
  ide.vscode.enable = true;
  
  # Global services
  globalServices = {
    postgres.enable = true;
    redis.enable = true;
  };
}
```

## Learn More

- [Stack Documentation](https://stack.dev/docs)
- [Quick Start Guide](https://stack.dev/docs/quick-start)
- [devenv Documentation](https://devenv.sh)
- [Flake Parts](https://flake.parts)
