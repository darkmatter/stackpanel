# Stackpanel Templates

Project templates for bootstrapping new Stackpanel projects.

> [!NOTE]
> If you change the options schema, or anything that would affect the config scema,
> PLEASE run `generate-template-configs` inside the devshell to regenerate the
> templates.

## Available Templates

| Template  | Description | Use Case                                     |
| --------- | ----------- | -------------------------------------------- |
| `default` | flake-parts | Full-featured, recommended for most projects |
| `minimal` | flake-parts | Minimal Stackpanel setup                     |

## Quick Start

```bash
mkdir myproject && cd myproject
nix flake init -t github:darkmatter/stackpanel
nix develop
```

## Template Details

### default (Recommended)

Full-featured setup with flake-parts integration.

```bash
nix flake init -t github:darkmatter/stackpanel
```

**Structure:**

```text
.
├── flake.nix              # Flake entry with flake-parts
├── .stack/
│   └── config.nix         # Stackpanel options
└── .envrc                 # direnv configuration
```

**Features:**

- Multi-platform support (Linux/Darwin, x86_64/aarch64)
- Stackpanel processes, services, and languages
- CLI, IDE, theme, and services integration

### minimal

Minimal setup using the same flake-parts module.

```bash
nix flake init -t github:darkmatter/stackpanel#minimal
```

**Structure:**

```text
.
├── flake.nix              # Flake entry with flake-parts
├── .stack/
│   └── config.nix         # Stackpanel options
└── .envrc                 # direnv configuration
```

**Features:**

- Fast pure evaluation
- Same Stackpanel module API as the default template
- Room to add custom `perSystem` outputs

## Addons

`stackpanel init` can offer optional, prompt-gated extras (e.g. "Install VS Code
integration?") that drop extra files and/or patch the project config based on
your answers. Addons are declared under [`_addons/`](./_addons/) and shared by
every template — see [`_addons/README.md`](./_addons/README.md) for the full
guide and the `_addons/_template/` scaffold for creating new ones.

## Configuration

All templates use the same `.stack/config.nix` structure:

```nix
{
  enable = true;
  theme.enable = true;
  ide.vscode.enable = true;
}
```

## Learn More

- [Stackpanel Documentation](https://stackpanel.dev/docs)
- [Quick Start Guide](https://stackpanel.dev/docs/quick-start)
- [Flake Parts](https://flake.parts)
