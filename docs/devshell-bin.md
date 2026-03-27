# Devshell Bin Package

The `devshell-bin` package is a Nix derivation that creates a directory containing symlinks to all binaries from the stack development shell. This allows you to access devshell tools without entering the shell.

## Usage

### Build the derivation

```bash
nix build .#devshell-bin
```

### Use the binaries

After building, the binaries are available in `./result/bin/`:

```bash
# Run any tool from the devshell
./result/bin/go version
./result/bin/air --help
./result/bin/jq --version

# Or add to PATH temporarily
export PATH="$PWD/result/bin:$PATH"
go version
```

### Install to profile

To make these tools available system-wide:

```bash
nix profile install .#devshell-bin
```

Then all devshell tools will be available in your PATH.

## How it works

The derivation:
1. Extracts all packages from the native devshell's `passthru.devshellConfig`
2. Creates symlinks in `$out/bin/` for every binary from every package
3. Handles conflicts by giving priority to the first package that provides a binary

## Implementation

- **Source**: `nix/flake/packages/devshell-bin.nix`
- **Flake integration**: `flake.nix` (lines 118-121, 129-131)
- **Dependencies**: Requires the native devshell (`nativeDevshell`) to be defined

## What's included

The derivation includes all packages defined in your stack configuration's `stack.packages` list. In the stack project itself, this includes:

- Development tools (air, nixd, git, jq, go, prek)
- AWS tools (aws cli, chamber, aws_signing_helper)
- Step CA tools (step certificate management)
- And all their dependencies' binaries

Total: 33 binaries (as of the initial build)
