# Flake integrations

External flakes (Prelude, process-compose, git-hooks, treefmt, …) register here
instead of growing `nix/flake/default.nix`.

## Interface

Each `integrations/<id>/default.nix` is a function:

```nix
{ localFlake, localInputs, inputs }:
{
  available = localInputs ? my-input;   # or `inputs ? …`
  flakeModules = [ … ];                # imported when available
  # flakeConfig = { lib, ... }: { … }; # optional top-level mkMerge arm
  # perSystem = ctx: { … };            # after stackpanel eval
  # extraShellPackages = ctx: [ pkg ]; # on PATH in devShells.default
}
```

`ctx` includes `spConfig`, `loadedConfig`, `pkgs`, `lib`, `self`, `inputs`,
`includeRootOutputs`, and the full eval result.

## Register

1. Add `integrations/<id>/default.nix` implementing the interface.
2. Add one attr in [`default.nix`](./default.nix) `all = { … }`.
3. Add the flake input in the root `flake.nix` when Stackpanel should ship it.

No `hasX` checks belong in the composer.

## Examples

| Id | Role |
| ---- | ------ |
| `prelude` | Shell DX (MOTD / menu / docs); builds bridged packages |
| `process-compose` | `flakeConfig` arm reading shell `passthru.processes` |
| `git-hooks` | Pre-commit check when enabled in config |
| `treefmt` | Root formatter/packages when `includeRootOutputs` |
