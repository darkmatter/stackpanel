# Containers Module

OCI container image building with nix2container or dockerTools.

## Overview

Builds container images for apps using either [nix2container](https://github.com/nlewo/nix2container) (default, layer-optimized) or nixpkgs `dockerTools`. Supports per-app container configuration and direct image definitions.

## Files

| File | Description |
|------|-------------|
| `default.nix` | Module entry point |
| `module.nix` | Container options and build logic |
| `builder.nix` | Linux builder detection and remote build helpers |
| `schema.nix` | Runtime container config fields shared by Nix and Studio |
| `ui.nix` | Web studio panel definitions |
| `meta.nix` | Module metadata |

## Usage

```nix
# Per-app containers
stackpanel.apps.web.container = {
  enable = true;
  type = "bun";
  port = 3000;
};

# Or direct image definitions
stackpanel.containers.images.my-image = {
  name = "my-app";
  type = "bun";
  port = 3000;
};
```

## Register an image builder

Both `apps.<app>.container.type` and `containers.images.<key>.type` select a
function in `stackpanel.containerBuilders`. The bundled IDs are `bun` (the
default), `node`, `go`, `static`, and `custom`. The Studio selector lists the
evaluated registry, including builders contributed by imported modules.

For example, a module packaging a Rust tool can register:

```nix
stackpanel.containerBuilders.rust-cli = { image, containerLib, ... }:
  let
    inherit (containerLib) pkgsLinux;
    appDir = pkgsLinux.runCommand "rg-root" {} ''
      mkdir -p $out/app
      ln -s ${pkgsLinux.ripgrep}/bin/rg $out/app/rg
    '';
  in
  containerLib.buildImage (image // {
    inherit appDir;
    defaultCommand = [ "/app/rg" "--version" ];
  });
```

`appName` is the image configuration key; `app` is the evaluated app for an
app-generated image, or `null` for a standalone image. `image` contains the
resolved `name`, `type`, `version`, `backend`, `projectRoot`, `buildOutputPath`,
`workingDir`, `port`, `env`, `startupCommand`, `copyToRoot`, `maxLayers`,
`registry`, and `defaultCopyArgs`. `pkgs` is for the host; use
`containerLib.pkgsLinux` for image contents.

Return `{ container, copyScript }`: a Linux image derivation and a host-runnable
script derivation (its output path is the executable). `buildImage` supplies
both for the selected backend, honoring the resolved registry and startup
overrides. Outputs remain `packages.<system>.container-<key>` and
`apps.<system>.copy-container-<key>`.

## Commands

| Command | Description |
|---------|-------------|
| `container-build <name>` | Build a container image |
| `container-copy <name>` | Build and push to registry |
| `container-run <name>` | Build and run locally |
