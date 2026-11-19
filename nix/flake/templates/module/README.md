# Example Stackpanel module

The root `flake.nix` exports `stackpanelModules.default` from `module.nix`. It has no inputs: a consuming project supplies `lib.stackpanel` and its app configuration. Add the module flake as a Stackpanel project input and set `modules.example.enable = true` in `.stack/config.nix` to display the number of configured apps.

## Edit with nixd

From an empty directory with flake-enabled Nix:

```sh
nix flake init -t github:darkmatter/stackpanel#module
nix flake lock ./dev
nix run --no-update-lock-file ./dev#nixd -- --version
```

In a Git repository, track the template files (including `dev/flake.nix`) before locking, then track `dev/flake.lock`. Commit that lock alongside the module to share the SDK and nixd revisions. Consumers do not import `dev/`.

Open and trust the **module root**, not `dev/`, in [VS Code with Nix IDE](https://github.com/nix-community/vscode-nix-ide#language-servers) or [Zed with the Nix extension](https://github.com/zed-extensions/nix#configuration). The workspace settings launch the command above without `--version`; `nix` must be on the editor's PATH. No global nixd, direnv, or generated settings are needed.

In `module.nix`, hover `label` or request completions inside `ui.widgets.appCount.metric`. The template points nixd's default option worker (`nixos`) at the raw `mkModule` declarations in `dev/flake.nix`'s `moduleAuthorOptions`, not at a consumer project. Inspect it with `nix eval ./dev#moduleAuthorOptions --apply builtins.attrNames --json`. To adopt a newer SDK, run `nix flake update stackpanel --flake ./dev` and restart the language server.

For helper names, request completion after `lib.stackpanel.ui.`. nixd gets those names and ordinary `pkgs` completions from the same locked inputs; it does not load NixOS options for this standalone module.
