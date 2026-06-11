# Stackpanel deploy sub-flake

This directory is a **stackpanel-internal** seam: NixOS deployment outputs live
here instead of on the main flake so tools like `nix flake check` and registry
pushers do not evaluate full machine configs during everyday development.

## Configuration

In `.stack/config.nix`:

```nix
stackpanel.deployment.flakeOutputs = {
  expose = false;
  flakeDir = "./deploy";
};

stackpanel.colmena.flake = "./deploy";
```

Framework users who want the default behavior leave `expose = true` (default)
and do not need a sub-flake.

## Commands

```bash
# Evaluate a machine config
nix eval ./deploy#nixosConfigurations.hzcloud-hel-1.config.system.build.toplevel.drvPath

# Colmena (also via colmena-apply when colmena.flake is set)
colmena apply --flake ./deploy --substitute-on-destination

# Provision / switch
nixos-anywhere --flake ./deploy#<machine> ...
nixos-rebuild switch --flake ./deploy#<machine> --target-host ...
```
