# IDE Module

IDE integration for VS Code and other editors.

## Overview

This module generates IDE configuration files that integrate the devenv shell with editor terminals. The generated files ensure that when you open a terminal in your IDE, it automatically loads the Nix development environment.

## Files

| File | Description |
|------|-------------|
| `ide.nix` | VS Code workspace and settings generation |
| `devshell.sh` | Shell loader script template |

## Generated Files

For VS Code, this module creates:

- **devshell-loader.sh**: Script that initializes the nix environment
- **\*.code-workspace**: Workspace file with terminal integration
- **settings.json** (optional): VS Code settings with terminal integration

## Usage

```nix
# devenv.nix
stackpanel.ide = {
  enable = true;
  vscode = {
    enable = true;
    workspace-name = "myproject";
    settings = {
      # Additional VS Code settings
    };
    extensions = [
      "ms-vscode-remote.remote-containers"
    ];
  };
};
```

## How It Works

1. Open the generated `.code-workspace` file in VS Code
2. When you open a new terminal, it runs `devshell-loader.sh`
3. The loader script initializes devenv and enters the development shell
4. All your packages, environment variables, and services are available
