# Flake integrations

Bundled compatibility adapters (Prelude, process-compose, git-hooks, treefmt)
and external flakes use the same hooks. No central registration is required.

## Interface

A consumer input can export a `stackpanelModuleMeta` attribute set with the
following hooks. A bundled `integrations/<id>/default.nix` returns the same set:

```nix
{ localFlake, localInputs, inputs }:
{
  available = localInputs ? my-input;   # or `inputs ? …`
  overlays = [ … ];                    # applied before pkgs is instantiated
  flakeModules = [ … ];                # imported when available
  # flakeConfig = { lib, ... }: { … }; # optional top-level mkMerge arm
  # perSystem = ctx: { … };            # after stackpanel eval
  # extraShellPackages = ctx: [ pkg ]; # on PATH in devShells.default
}
```

`ctx` includes `spConfig`, `loadedConfig`, `pkgs`, `lib`, `self`, `inputs`,
`includeRootOutputs`, and the full eval result.

## Register

For external integrations, export `stackpanelModuleMeta.flakeModules` and/or
`stackpanelModuleMeta.overlays`. `overlays.stackpanel` is also recognized when
`stackpanelModuleMeta.overlays` is absent. These are static flake hooks, not
project module definitions: they cannot depend on Stackpanel configuration.
Bundled adapters are discovered from subdirectories containing `default.nix`.
Caller overlays are appended last. A consumer explicitly setting
`perSystem._module.args.pkgs` supplies its own overlay configuration.

## Examples

| Id | Role |
| ---- | ------ |
| `prelude` | Shell DX (MOTD / menu / docs); builds bridged packages |
| `process-compose` | `flakeConfig` arm reading shell `passthru.processes` |
| `git-hooks` | Pre-commit check when enabled in config |
| `treefmt` | Root formatter/packages when `includeRootOutputs` |

For Nix formatting, enable `git-hooks.nixfmt.enable` in `.stack/config.nix`.
FlakeHub evaluates the hook on every supported system. To check the same
derivations without publishing:

```sh
nix eval --json .#checks --apply 'builtins.mapAttrs (_: checks: checks.pre-commit-check.drvPath)'
```
