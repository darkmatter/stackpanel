# nix/flake/templates/

Project templates for bootstrapping new stackpanel projects.

## Overview

These templates provide ready-to-use project structures for common stackpanel use cases. Use `nix flake init` to bootstrap a new project.

## Available Templates

### default

A complete flake-parts project with:
- Multi-platform support (Linux/Darwin, x86_64/aarch64)
- Team-based secrets management with age encryption
- GitHub Actions CI/CD integration
- Modular architecture

```bash
nix flake init -t github:stack-panel/nix#default
```

**Structure:**
```
.
├── flake.nix
└── .stackpanel/
    └── team.nix
```

### devenv

A minimal devenv.nix template showcasing stackpanel features:
- AWS Roles Anywhere integration
- Step CA certificate management
- Secrets handling
- Language support examples

```bash
nix flake init -t github:stack-panel/nix#devenv
```

## Template Files

### default/flake.nix

Starter flake with:
- nixpkgs and flake-parts inputs
- stackpanel module imports (commented until published)
- perSystem configuration for secrets and CI
- Example package output

### default/.stackpanel/team.nix

Team member registry for secrets management:
- Maps usernames to public keys
- Supports GitHub key sync via agent
- Admin role designation
- Safe to commit (public keys only)

### devenv/devenv.nix

Example devenv configuration with:
- Basic package setup
- Commented stackpanel feature examples
- Language configuration (JavaScript/Node.js)
- Process management hints
- Welcome message in enterShell

## Usage

### Initialize from Template

```bash
# In a new project directory
nix flake init -t github:stack-panel/nix#default

# Or for devenv template
nix flake init -t github:stack-panel/nix#devenv
```

### Add Team Members

Edit `.stackpanel/team.nix`:
```nix
{
  users = {
    alice = {
      github = "alice";
      pubkey = "ssh-ed25519 AAAA...";
      admin = true;
    };
  };
}
```

Or sync from GitHub:
```bash
stackpanel team sync alice bob charlie
```

### Configure Secrets

In `flake.nix`:
```nix
stackpanel.secrets = {
  enable = true;
  users = teamData.users;
  secrets = {
    "api-key.age".owners = [ "alice" "bob" ];
  };
};
```

### Enable CI/CD

```nix
stackpanel.ci.github = {
  enable = true;
  checks = {
    enable = true;
    commands = [ "nix flake check" ];
  };
};
```

## Customization

Templates are starting points. After initialization:

1. Update the description in `flake.nix`
2. Add your team members
3. Configure secrets for your project
4. Enable relevant stackpanel features
5. Add your packages and development tools
